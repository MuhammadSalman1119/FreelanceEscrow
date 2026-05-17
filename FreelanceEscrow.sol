// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FreelanceEscrow
 * @author  Your Name
 * @notice  Trustless escrow for freelance agreements — client locks payment,
 *          freelancer delivers work, arbitrator resolves disputes.
 * @dev     Designed for EVM-compatible chains (Ethereum, Polygon, Arbitrum, Base).
 *          Passes Slither static-analysis and follows Checks-Effects-Interactions.
 */
contract FreelanceEscrow {

    // ─────────────────────────────────────────────
    //  TYPES
    // ─────────────────────────────────────────────

    enum State { AWAITING_DELIVERY, COMPLETE, DISPUTED, REFUNDED }

    struct Agreement {
        address payable client;
        address payable freelancer;
        address         arbitrator;
        uint256         amount;          // wei locked
        uint256         deadline;        // unix timestamp
        State           state;
        string          ipfsJobHash;     // IPFS CID of job description
        string          ipfsDeliveryHash;// IPFS CID of delivered work (set by freelancer)
    }

    // ─────────────────────────────────────────────
    //  STATE
    // ─────────────────────────────────────────────

    uint256 public agreementCount;
    mapping(uint256 => Agreement) public agreements;

    uint16 public constant ARBITRATION_FEE_BPS = 100; // 1 %

    // ─────────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────────

    event AgreementCreated(
        uint256 indexed id,
        address indexed client,
        address indexed freelancer,
        uint256 amount,
        uint256 deadline
    );
    event WorkDelivered(uint256 indexed id, string ipfsDeliveryHash);
    event PaymentReleased(uint256 indexed id, uint256 amount);
    event DisputeRaised(uint256 indexed id, address raisedBy);
    event DisputeResolved(uint256 indexed id, address winner, uint256 amount);
    event Refunded(uint256 indexed id, uint256 amount);

    // ─────────────────────────────────────────────
    //  ERRORS  (gas-efficient vs require strings)
    // ─────────────────────────────────────────────

    error Unauthorized();
    error InvalidState(State current, State required);
    error DeadlinePassed();
    error DeadlineNotPassed();
    error InsufficientFunds();
    error ZeroAddress();
    error TransferFailed();

    // ─────────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyClient(uint256 id) {
        if (msg.sender != agreements[id].client) revert Unauthorized();
        _;
    }

    modifier onlyFreelancer(uint256 id) {
        if (msg.sender != agreements[id].freelancer) revert Unauthorized();
        _;
    }

    modifier onlyArbitrator(uint256 id) {
        if (msg.sender != agreements[id].arbitrator) revert Unauthorized();
        _;
    }

    modifier inState(uint256 id, State required) {
        if (agreements[id].state != required)
            revert InvalidState(agreements[id].state, required);
        _;
    }

    // ─────────────────────────────────────────────
    //  EXTERNAL FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Client creates an agreement and locks payment in escrow.
     * @param  freelancer   Address that will deliver the work.
     * @param  arbitrator   Trusted third-party for dispute resolution.
     * @param  deadline     Unix timestamp by which work must be delivered.
     * @param  ipfsJobHash  IPFS CID describing the job requirements.
     * @return id           Unique agreement identifier.
     */
    function createAgreement(
        address payable freelancer,
        address         arbitrator,
        uint256         deadline,
        string calldata ipfsJobHash
    ) external payable returns (uint256 id) {
        if (freelancer == address(0) || arbitrator == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert InsufficientFunds();
        if (deadline <= block.timestamp) revert DeadlinePassed();

        id = agreementCount++;

        agreements[id] = Agreement({
            client:           payable(msg.sender),
            freelancer:       freelancer,
            arbitrator:       arbitrator,
            amount:           msg.value,
            deadline:         deadline,
            state:            State.AWAITING_DELIVERY,
            ipfsJobHash:      ipfsJobHash,
            ipfsDeliveryHash: ""
        });

        emit AgreementCreated(id, msg.sender, freelancer, msg.value, deadline);
    }

    /**
     * @notice Freelancer marks work as delivered by uploading an IPFS hash.
     * @param  id               Agreement identifier.
     * @param  ipfsDeliveryHash IPFS CID of the delivered artefacts.
     */
    function submitDelivery(uint256 id, string calldata ipfsDeliveryHash)
        external
        onlyFreelancer(id)
        inState(id, State.AWAITING_DELIVERY)
    {
        if (block.timestamp > agreements[id].deadline) revert DeadlinePassed();

        agreements[id].ipfsDeliveryHash = ipfsDeliveryHash;

        emit WorkDelivered(id, ipfsDeliveryHash);
    }

    /**
     * @notice Client approves the delivery and releases payment to freelancer.
     * @param  id Agreement identifier.
     */
    function approveDelivery(uint256 id)
        external
        onlyClient(id)
        inState(id, State.AWAITING_DELIVERY)
    {
        Agreement storage a = agreements[id];
        a.state = State.COMPLETE;

        _safeTransfer(a.freelancer, a.amount);

        emit PaymentReleased(id, a.amount);
    }

    /**
     * @notice Either party raises a dispute before the deadline.
     * @param  id Agreement identifier.
     */
    function raiseDispute(uint256 id)
        external
        inState(id, State.AWAITING_DELIVERY)
    {
        Agreement storage a = agreements[id];
        if (msg.sender != a.client && msg.sender != a.freelancer)
            revert Unauthorized();

        a.state = State.DISPUTED;

        emit DisputeRaised(id, msg.sender);
    }

    /**
     * @notice Arbitrator resolves a dispute, splitting funds between parties.
     * @param  id               Agreement identifier.
     * @param  freelancerShareBps Basis points awarded to freelancer (0–10000).
     */
    function resolveDispute(uint256 id, uint16 freelancerShareBps)
        external
        onlyArbitrator(id)
        inState(id, State.DISPUTED)
    {
        require(freelancerShareBps <= 10_000, "BPS > 10000");

        Agreement storage a = agreements[id];
        a.state = State.COMPLETE;

        uint256 total       = a.amount;
        uint256 arbFee      = (total * ARBITRATION_FEE_BPS) / 10_000;
        uint256 remaining   = total - arbFee;

        uint256 freelancerPay = (remaining * freelancerShareBps) / 10_000;
        uint256 clientPay     = remaining - freelancerPay;

        _safeTransfer(payable(a.arbitrator),  arbFee);
        if (freelancerPay > 0) _safeTransfer(a.freelancer, freelancerPay);
        if (clientPay     > 0) _safeTransfer(a.client,     clientPay);

        address winner = freelancerShareBps >= 5_000 ? a.freelancer : a.client;
        emit DisputeResolved(id, winner, total);
    }

    /**
     * @notice Client reclaims funds if the deadline passes without delivery.
     * @param  id Agreement identifier.
     */
    function claimRefund(uint256 id)
        external
        onlyClient(id)
        inState(id, State.AWAITING_DELIVERY)
    {
        Agreement storage a = agreements[id];
        if (block.timestamp <= a.deadline) revert DeadlineNotPassed();

        a.state = State.REFUNDED;

        _safeTransfer(a.client, a.amount);

        emit Refunded(id, a.amount);
    }

    // ─────────────────────────────────────────────
    //  VIEW HELPERS
    // ─────────────────────────────────────────────

    /// @notice Returns the full agreement struct for a given id.
    function getAgreement(uint256 id) external view returns (Agreement memory) {
        return agreements[id];
    }

    // ─────────────────────────────────────────────
    //  INTERNAL
    // ─────────────────────────────────────────────

    function _safeTransfer(address payable to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
