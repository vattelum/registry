// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {
    IDocumentRegistry,
    Document,
    DocumentReference,
    DOC_TYPE_ORIGINAL,
    DOC_TYPE_AMENDMENT,
    DOC_TYPE_REVISION,
    DOC_TYPE_REPEAL,
    DOC_TYPE_CODIFICATION
} from "@vattelum/document-registry/DocumentRegistry.sol";

/// @title Registry — On-Chain Document Registry (single-admin)
/// @notice Append-only registry of documents organised by category with a document
///         layer (categories as folders containing independent documents), external
///         references, and per-document amendment restrictions enforced on-chain.
///
///         Single-admin governance. Conforms to IDocumentRegistry — interoperable
///         with the Vattelum Document Registry standard so other registries (DAA,
///         BVS, SCB, individual contracts) can cite Registry documents using the
///         shared (registryAddress, chainId, categoryId, documentId, version) tuple.
///
///         Hard-lock semantics: while a document's lock window is active, neither
///         `addDocument` (for amend-family docTypes targeting it) nor
///         `setAmendmentRestrictions` may touch the document. The admin self-binds
///         for the lock duration. After the window expires, the admin regains free
///         access to modify, re-lock, or amend. This is /registry-specific because
///         /registry has no voting layer to substitute for the constraint.
contract Registry is IDocumentRegistry {
    // ──────────────────────── Structs ──────────────────────────

    struct DocumentInput {
        uint256 categoryId;
        uint256 documentId; // 0 = create new document, > 0 = amend existing
        string contentUri; // ar://… ipfs://… https://… (storage-agnostic)
        bytes32 contentHash; // SHA-256 of trimmed UTF-8 body
        string title;
        string voteId; // empty string by default; reserved for future external-ID use
        uint8 docType;
    }

    struct AmendmentRestrictions {
        uint256 minTimeBetweenAmendments;
        uint256 lastAmendmentTime;
        uint256[] lockedSections;
    }

    // ──────────────────────── State ───────────────────────────

    address public admin;
    mapping(uint256 => string) public categoryNames;
    uint256 public categoryCount;
    mapping(uint256 => uint256) private _documentCounts;
    mapping(uint256 => mapping(uint256 => uint256)) private _versionCounts;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => Document))) private _documents;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => DocumentReference[]))) private _references;
    mapping(uint256 => mapping(uint256 => AmendmentRestrictions)) private _amendmentRestrictions;

    // ──────────────────────── Events ──────────────────────────

    event CategoryAdded(uint256 indexed categoryId, string name);
    event DocumentAdded(
        uint256 indexed categoryId,
        uint256 indexed documentId,
        uint256 indexed version,
        string contentUri,
        bytes32 contentHash,
        uint8 docType
    );
    event AdminTransferred(address indexed previous, address indexed current);
    event AmendmentRestrictionsUpdated(uint256 indexed categoryId, uint256 indexed documentId);

    // ──────────────────────── Errors ──────────────────────────

    error NotAdmin();
    error InvalidAdmin();
    error CategoryDoesNotExist(uint256 categoryId);
    error DocumentDoesNotExist(uint256 categoryId, uint256 documentId);
    error VersionDoesNotExist(uint256 categoryId, uint256 documentId, uint256 version);
    error AmendmentTooSoon(uint256 categoryId, uint256 documentId, uint256 earliestAllowed);
    error SectionLocked(uint256 categoryId, uint256 documentId, uint256 lockedSection);
    error RestrictionsLocked(uint256 categoryId, uint256 documentId, uint256 earliestAllowed);

    // ──────────────────────── Modifier ────────────────────────

    modifier onlyAdmin() {
        _requireAdmin();
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
    /// @param input Document metadata. documentId = 0 creates a new document, > 0 amends existing.
    /// @param refs Array of DocumentReferences (can be empty). For amend-family docTypes,
    ///             refs[0] should carry the target citation per Vattelum C&R standard.
    /// @return documentId The document ID (new or existing).
    /// @return version The auto-incremented version number assigned.
    function addDocument(DocumentInput calldata input, DocumentReference[] calldata refs)
        external
        onlyAdmin
        returns (uint256 documentId, uint256 version)
    {
        _requireCategory(input.categoryId);

        if (input.documentId == 0) {
            documentId = ++_documentCounts[input.categoryId];
        } else {
            if (input.documentId > _documentCounts[input.categoryId]) {
                revert DocumentDoesNotExist(input.categoryId, input.documentId);
            }
            documentId = input.documentId;
        }

        AmendmentRestrictions storage restrictions = _amendmentRestrictions[input.categoryId][documentId];
        if (
            restrictions.minTimeBetweenAmendments > 0 && restrictions.lastAmendmentTime > 0
                && block.timestamp < restrictions.lastAmendmentTime + restrictions.minTimeBetweenAmendments
        ) {
            revert AmendmentTooSoon(
                input.categoryId, documentId, restrictions.lastAmendmentTime + restrictions.minTimeBetweenAmendments
            );
        }

        // Amendment-family docTypes (Amendment, Revision, Repeal) may not target a locked
        // section. refs[0] carries the target per Vattelum C&R; when refs[0] points at a
        // local document, its lockedSections govern. Cross-registry refs are not enforced
        // on-chain — out of scope, by design.
        if (
            input.docType == DOC_TYPE_AMENDMENT || input.docType == DOC_TYPE_REVISION
                || input.docType == DOC_TYPE_REPEAL
        ) {
            if (refs.length > 0 && refs[0].registryAddress == address(this)) {
                uint256 targetCat = refs[0].categoryId;
                uint256 targetDoc = refs[0].documentId;
                if (targetCat < categoryCount && targetDoc > 0 && targetDoc <= _documentCounts[targetCat]) {
                    _checkLockedSections(
                        refs[0].targetSection,
                        _amendmentRestrictions[targetCat][targetDoc].lockedSections,
                        targetCat,
                        targetDoc
                    );
                }
            }
        }

        version = ++_versionCounts[input.categoryId][documentId];

        _documents[input.categoryId][documentId][version] = Document({
            contentUri: input.contentUri,
            contentHash: input.contentHash,
            title: input.title,
            version: version,
            timestamp: block.timestamp,
            voteId: input.voteId,
            docType: input.docType
        });

        for (uint256 i = 0; i < refs.length; i++) {
            _references[input.categoryId][documentId][version].push(refs[i]);
        }

        if (restrictions.minTimeBetweenAmendments > 0) {
            restrictions.lastAmendmentTime = block.timestamp;
        }

        emit DocumentAdded(
            input.categoryId, documentId, version, input.contentUri, input.contentHash, input.docType
        );
    }

    // ──────────────────────── Read Functions ──────────────────

    /// @notice Retrieve a specific document version.
    function getDocument(uint256 categoryId, uint256 documentId, uint256 version)
        external
        view
        override
        returns (Document memory)
    {
        _requireDocument(categoryId, documentId);
        if (version == 0 || version > _versionCounts[categoryId][documentId]) {
            revert VersionDoesNotExist(categoryId, documentId, version);
        }
        return _documents[categoryId][documentId][version];
    }

    /// @notice Retrieve the most recent version of a document.
    function getLatest(uint256 categoryId, uint256 documentId) external view returns (Document memory) {
        _requireDocument(categoryId, documentId);
        uint256 latest = _versionCounts[categoryId][documentId];
        if (latest == 0) {
            revert VersionDoesNotExist(categoryId, documentId, 0);
        }
        return _documents[categoryId][documentId][latest];
    }

    /// @notice Retrieve all versions of a document, in order (1 → N).
    function getHistory(uint256 categoryId, uint256 documentId)
        external
        view
        override
        returns (Document[] memory)
    {
        _requireDocument(categoryId, documentId);
        uint256 count = _versionCounts[categoryId][documentId];
        Document[] memory docs = new Document[](count);
        for (uint256 i = 0; i < count; i++) {
            docs[i] = _documents[categoryId][documentId][i + 1];
        }
        return docs;
    }

    /// @notice Retrieve external references for a document version.
    function getReferences(uint256 categoryId, uint256 documentId, uint256 version)
        external
        view
        override
        returns (DocumentReference[] memory)
    {
        _requireDocument(categoryId, documentId);
        if (version == 0 || version > _versionCounts[categoryId][documentId]) {
            revert VersionDoesNotExist(categoryId, documentId, version);
        }
        return _references[categoryId][documentId][version];
    }

    /// @notice Retrieve the version count for a document.
    function getVersionCount(uint256 categoryId, uint256 documentId) external view returns (uint256) {
        _requireDocument(categoryId, documentId);
        return _versionCounts[categoryId][documentId];
    }

    /// @notice Retrieve the document count for a category.
    function getDocumentCount(uint256 categoryId) external view returns (uint256) {
        _requireCategory(categoryId);
        return _documentCounts[categoryId];
    }

    /// @notice Retrieve amendment restrictions for a document.
    function getAmendmentRestrictions(uint256 categoryId, uint256 documentId)
        external
        view
        returns (uint256 minTimeBetweenAmendments, uint256 lastAmendmentTime, uint256[] memory lockedSections)
    {
        _requireDocument(categoryId, documentId);
        AmendmentRestrictions storage r = _amendmentRestrictions[categoryId][documentId];
        return (r.minTimeBetweenAmendments, r.lastAmendmentTime, r.lockedSections);
    }

    // ──────────────────────── Admin ──────────────────────────

    /// @notice Transfer admin to a new address.
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) {
            revert InvalidAdmin();
        }
        address previous = admin;
        admin = newAdmin;
        emit AdminTransferred(previous, newAdmin);
    }

    /// @notice Configure amendment restrictions for a document.
    /// @dev Hard-lock: while currently locked, this call reverts RestrictionsLocked —
    ///      no field on the restrictions struct can be modified by anyone, including
    ///      admin, until the lock window elapses. When `minTimeBetweenAmendments > 0`,
    ///      `lastAmendmentTime` is anchored to NOW so a fresh lock starts at this call.
    function setAmendmentRestrictions(
        uint256 categoryId,
        uint256 documentId,
        uint256 minTimeBetweenAmendments,
        uint256[] calldata lockedSections
    ) external onlyAdmin {
        _requireDocument(categoryId, documentId);
        AmendmentRestrictions storage r = _amendmentRestrictions[categoryId][documentId];

        if (
            r.minTimeBetweenAmendments > 0 && r.lastAmendmentTime > 0
                && block.timestamp < r.lastAmendmentTime + r.minTimeBetweenAmendments
        ) {
            revert RestrictionsLocked(categoryId, documentId, r.lastAmendmentTime + r.minTimeBetweenAmendments);
        }

        r.minTimeBetweenAmendments = minTimeBetweenAmendments;
        r.lockedSections = lockedSections;

        if (minTimeBetweenAmendments > 0) {
            r.lastAmendmentTime = block.timestamp;
        }

        emit AmendmentRestrictionsUpdated(categoryId, documentId);
    }

    // ──────────────────────── Internal ────────────────────────

    function _requireAdmin() internal view {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
    }

    function _requireCategory(uint256 categoryId) internal view {
        if (categoryId >= categoryCount) {
            revert CategoryDoesNotExist(categoryId);
        }
    }

    function _requireDocument(uint256 categoryId, uint256 documentId) internal view {
        _requireCategory(categoryId);
        if (documentId == 0 || documentId > _documentCounts[categoryId]) {
            revert DocumentDoesNotExist(categoryId, documentId);
        }
    }

    /// @dev Parse a targetSection string (e.g. "3", "3.1", "3,5,7.2") and revert if any
    ///      root section number appears in the provided lockedSections. Digits before a
    ///      '.' or ',' form the root; non-digit characters terminate the current number.
    function _checkLockedSections(
        string memory targetSection,
        uint256[] storage lockedSections,
        uint256 targetCategoryId,
        uint256 targetDocumentId
    ) internal view {
        if (lockedSections.length == 0) return;
        bytes memory bs = bytes(targetSection);
        if (bs.length == 0) return;

        uint256 current = 0;
        bool reading = true;
        bool hasDigit = false;

        for (uint256 i = 0; i < bs.length; i++) {
            bytes1 c = bs[i];
            if (c == 0x2C /* ',' */ ) {
                if (hasDigit) {
                    _revertIfLocked(current, lockedSections, targetCategoryId, targetDocumentId);
                }
                current = 0;
                reading = true;
                hasDigit = false;
            } else if (c == 0x2E /* '.' */ ) {
                reading = false;
            } else if (reading && c >= 0x30 && c <= 0x39) {
                current = current * 10 + (uint8(c) - 0x30);
                hasDigit = true;
            }
        }
        if (hasDigit) {
            _revertIfLocked(current, lockedSections, targetCategoryId, targetDocumentId);
        }
    }

    function _revertIfLocked(
        uint256 sectionNumber,
        uint256[] storage lockedSections,
        uint256 targetCategoryId,
        uint256 targetDocumentId
    ) internal view {
        for (uint256 i = 0; i < lockedSections.length; i++) {
            if (lockedSections[i] == sectionNumber) {
                revert SectionLocked(targetCategoryId, targetDocumentId, sectionNumber);
            }
        }
    }
}
