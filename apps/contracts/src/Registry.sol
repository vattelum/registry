// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Registry — On-Chain Document Registry
/// @notice Append-only registry of legislation organized by category with version
///         history, external references, and configurable amendment restrictions.
///         Single admin (deployer), transferable.
contract Registry {
    // ──────────────────────── Structs ──────────────────────────

    struct Document {
        string arweaveTxId;
        bytes32 contentHash;
        string title;
        uint256 version;
        uint256 timestamp;
        uint8 docType;
    }

    struct DocumentInput {
        uint256 categoryId;
        string arweaveTxId;
        bytes32 contentHash;
        string title;
        uint8 docType;
    }

    struct ExternalReference {
        address registryAddress;
        uint256 chainId;
        uint256 categoryId;
        uint256 version;
        uint8 relationType;
        string targetSection;
    }

    struct AmendmentRestrictions {
        uint256 minTimeBetweenAmendments;
        uint256 lastAmendmentTime;
        uint256[] lockedSections;
        uint256 coreThreshold;
    }

    // ──────────────────────── State ───────────────────────────

    address public admin;
    mapping(uint256 => string) public categoryNames;
    uint256 public categoryCount;
    mapping(uint256 => uint256) private _versionCounts;
    mapping(uint256 => mapping(uint256 => Document)) private _documents;
    mapping(uint256 => mapping(uint256 => ExternalReference[])) private _references;
    mapping(uint256 => AmendmentRestrictions) private _amendmentRestrictions;

    // ──────────────────────── Events ──────────────────────────

    event CategoryAdded(uint256 indexed categoryId, string name);
    event DocumentRegistered(
        uint256 indexed categoryId,
        uint256 indexed version,
        string arweaveTxId,
        bytes32 contentHash,
        uint8 docType
    );
    event AdminTransferred(address indexed previous, address indexed current);
    event AmendmentRestrictionsUpdated(uint256 indexed categoryId);

    // ──────────────────────── Errors ──────────────────────────

    error NotAdmin();
    error CategoryDoesNotExist(uint256 categoryId);
    error VersionDoesNotExist(uint256 categoryId, uint256 version);
    error AmendmentTooSoon(uint256 categoryId, uint256 earliestAllowed);
    error InvalidAdmin();

    // ──────────────────────── Modifier ────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
        _;
    }

    // ──────────────────────── Constructor ─────────────────────

    constructor(address _admin) {
        if (_admin == address(0)) {
            revert InvalidAdmin();
        }
        admin = _admin;
        emit AdminTransferred(address(0), _admin);
    }

    // ──────────────────────── Public / External ──────────────

    /// @notice Create a new document category.
    /// @param name Human-readable category name.
    /// @return categoryId The sequential ID assigned to the new category.
    function addCategory(string calldata name) external onlyAdmin returns (uint256) {
        uint256 categoryId = categoryCount++;
        categoryNames[categoryId] = name;

        emit CategoryAdded(categoryId, name);
        return categoryId;
    }

    /// @notice Register a document on-chain. Append-only.
    /// @param input Document metadata grouped in a struct.
    /// @param refs Array of external references (can be empty).
    /// @return version The auto-incremented version number assigned.
    function addDocument(DocumentInput calldata input, ExternalReference[] calldata refs)
        external
        onlyAdmin
        returns (uint256)
    {
        if (input.categoryId >= categoryCount) {
            revert CategoryDoesNotExist(input.categoryId);
        }

        AmendmentRestrictions storage restrictions = _amendmentRestrictions[input.categoryId];
        if (
            restrictions.minTimeBetweenAmendments > 0
                && restrictions.lastAmendmentTime > 0
                && block.timestamp < restrictions.lastAmendmentTime + restrictions.minTimeBetweenAmendments
        ) {
            revert AmendmentTooSoon(
                input.categoryId, restrictions.lastAmendmentTime + restrictions.minTimeBetweenAmendments
            );
        }

        uint256 version = ++_versionCounts[input.categoryId];

        _documents[input.categoryId][version] = Document({
            arweaveTxId: input.arweaveTxId,
            contentHash: input.contentHash,
            title: input.title,
            version: version,
            timestamp: block.timestamp,
            docType: input.docType
        });

        for (uint256 i = 0; i < refs.length; i++) {
            _references[input.categoryId][version].push(refs[i]);
        }

        restrictions.lastAmendmentTime = block.timestamp;

        emit DocumentRegistered(input.categoryId, version, input.arweaveTxId, input.contentHash, input.docType);
        return version;
    }

    // ──────────────────────── Read Functions ──────────────────

    /// @notice Retrieve a specific document version.
    function getDocument(uint256 categoryId, uint256 version) external view returns (Document memory) {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        if (version == 0 || version > _versionCounts[categoryId]) {
            revert VersionDoesNotExist(categoryId, version);
        }
        return _documents[categoryId][version];
    }

    /// @notice Retrieve the most recent version in a category.
    function getLatest(uint256 categoryId) external view returns (Document memory) {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        uint256 latest = _versionCounts[categoryId];
        if (latest == 0) {
            revert VersionDoesNotExist(categoryId, 0);
        }
        return _documents[categoryId][latest];
    }

    /// @notice Retrieve all versions in a category.
    function getHistory(uint256 categoryId) external view returns (Document[] memory) {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        uint256 count = _versionCounts[categoryId];
        Document[] memory docs = new Document[](count);
        for (uint256 i = 0; i < count; i++) {
            docs[i] = _documents[categoryId][i + 1];
        }
        return docs;
    }

    /// @notice Retrieve external references for a document version.
    function getReferences(uint256 categoryId, uint256 version)
        external
        view
        returns (ExternalReference[] memory)
    {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        if (version == 0 || version > _versionCounts[categoryId]) {
            revert VersionDoesNotExist(categoryId, version);
        }
        return _references[categoryId][version];
    }

    /// @notice Retrieve the version count for a category.
    function getVersionCount(uint256 categoryId) external view returns (uint256) {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        return _versionCounts[categoryId];
    }

    /// @notice Retrieve amendment restrictions for a category.
    function getAmendmentRestrictions(uint256 categoryId)
        external
        view
        returns (uint256 minTimeBetweenAmendments, uint256 lastAmendmentTime, uint256[] memory lockedSections, uint256 coreThreshold)
    {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        AmendmentRestrictions storage r = _amendmentRestrictions[categoryId];
        return (r.minTimeBetweenAmendments, r.lastAmendmentTime, r.lockedSections, r.coreThreshold);
    }

    // ──────────────────────── Admin ──────────────────────────

    /// @notice Transfer admin to a new address.
    /// @param newAdmin The new admin (cannot be address(0)).
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) {
            revert InvalidAdmin();
        }
        address previous = admin;
        admin = newAdmin;
        emit AdminTransferred(previous, newAdmin);
    }

    /// @notice Configure amendment restrictions for a category.
    function setAmendmentRestrictions(
        uint256 categoryId,
        uint256 minTimeBetweenAmendments,
        uint256[] calldata lockedSections,
        uint256 coreThreshold
    ) external onlyAdmin {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
        AmendmentRestrictions storage r = _amendmentRestrictions[categoryId];
        r.minTimeBetweenAmendments = minTimeBetweenAmendments;
        r.lockedSections = lockedSections;
        r.coreThreshold = coreThreshold;

        emit AmendmentRestrictionsUpdated(categoryId);
    }
}
