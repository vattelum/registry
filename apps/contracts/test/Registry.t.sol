// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {
    IDocumentRegistry,
    Document,
    DocumentReference,
    DOC_TYPE_ORIGINAL,
    DOC_TYPE_AMENDMENT,
    DOC_TYPE_REVISION,
    DOC_TYPE_REPEAL,
    DOC_TYPE_CODIFICATION,
    RELATION_AMENDS,
    RELATION_REVISES,
    RELATION_REPEALS,
    RELATION_GOVERNS,
    RELATION_REFERENCES
} from "@vattelum/document-registry/DocumentRegistry.sol";

contract RegistryTest is Test {
    Registry registry;

    address admin = makeAddr("admin");
    address stranger = makeAddr("stranger");
    address newAdmin = makeAddr("newAdmin");

    bytes32 constant HASH_A = keccak256("document-a");
    bytes32 constant HASH_B = keccak256("document-b");
    bytes32 constant HASH_C = keccak256("document-c");

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

    function setUp() public {
        registry = new Registry(admin);
    }

    // ──────────────── Helpers ────────────────────────────────

    function _createCategory(string memory name) internal returns (uint256) {
        vm.prank(admin);
        return registry.addCategory(name);
    }

    function _newDoc(uint256 categoryId, string memory uri, bytes32 hash, string memory title, uint8 docType)
        internal
        returns (uint256 documentId, uint256 version)
    {
        DocumentReference[] memory refs = new DocumentReference[](0);
        return _addDoc(categoryId, 0, uri, hash, title, docType, refs);
    }

    function _amendDoc(
        uint256 categoryId,
        uint256 documentId,
        string memory uri,
        bytes32 hash,
        string memory title,
        uint8 docType,
        DocumentReference[] memory refs
    ) internal returns (uint256, uint256) {
        return _addDoc(categoryId, documentId, uri, hash, title, docType, refs);
    }

    function _addDoc(
        uint256 categoryId,
        uint256 documentId,
        string memory uri,
        bytes32 hash,
        string memory title,
        uint8 docType,
        DocumentReference[] memory refs
    ) internal returns (uint256, uint256) {
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: categoryId,
            documentId: documentId,
            contentUri: uri,
            contentHash: hash,
            title: title,
            voteId: "",
            docType: docType
        });
        vm.prank(admin);
        return registry.addDocument(input, refs);
    }

    function _ref(uint256 categoryId, uint256 documentId, uint256 version, uint8 relationType, string memory section)
        internal
        view
        returns (DocumentReference memory)
    {
        return DocumentReference({
            registryAddress: address(registry),
            chainId: block.chainid,
            categoryId: categoryId,
            documentId: documentId,
            version: version,
            relationType: relationType,
            targetSection: section
        });
    }

    // ──────────────── addCategory ───────────────────────────

    function test_addCategory_createsWithSequentialId() public {
        uint256 id0 = _createCategory("Universal Standards");
        uint256 id1 = _createCategory("Blockchain Standards");

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(registry.categoryCount(), 2);
        assertEq(registry.categoryNames(0), "Universal Standards");
        assertEq(registry.categoryNames(1), "Blockchain Standards");
    }

    function test_addCategory_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit CategoryAdded(0, "Universal Standards");
        registry.addCategory("Universal Standards");
    }

    function test_addCategory_revertsForNonAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.addCategory("Unauthorized");
    }

    // ──────────────── addDocument: new vs amend ─────────────

    function test_addDocument_newDocument_assignsDocumentId1AndVersion1() public {
        _createCategory("Universal Standards");
        (uint256 documentId, uint256 version) =
            _newDoc(0, "ar://abc", HASH_A, "Article 1", DOC_TYPE_ORIGINAL);

        assertEq(documentId, 1);
        assertEq(version, 1);

        Document memory doc = registry.getDocument(0, 1, 1);
        assertEq(doc.contentUri, "ar://abc");
        assertEq(doc.contentHash, HASH_A);
        assertEq(doc.title, "Article 1");
        assertEq(doc.version, 1);
        assertEq(doc.timestamp, block.timestamp);
        assertEq(doc.voteId, "");
        assertEq(doc.docType, DOC_TYPE_ORIGINAL);
    }

    function test_addDocument_subsequentDocuments_incrementDocumentId() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Doc One", DOC_TYPE_ORIGINAL);
        (uint256 d2,) = _newDoc(0, "ar://2", HASH_B, "Doc Two", DOC_TYPE_ORIGINAL);

        assertEq(d1, 1);
        assertEq(d2, 2);
        assertEq(registry.getDocumentCount(0), 2);
    }

    function test_addDocument_amendExisting_incrementsVersion() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://v1", HASH_A, "V1", DOC_TYPE_ORIGINAL);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "");
        (uint256 d1again, uint256 v2) =
            _amendDoc(0, d1, "ar://v2", HASH_B, "V1 Amended", DOC_TYPE_AMENDMENT, refs);

        assertEq(d1again, 1);
        assertEq(v2, 2);
        assertEq(registry.getVersionCount(0, 1), 2);
        assertEq(registry.getDocument(0, 1, 2).title, "V1 Amended");
    }

    function test_addDocument_amendNonexistentDocument_reverts() public {
        _createCategory("Universal Standards");
        DocumentReference[] memory refs = new DocumentReference[](0);
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: 99,
            contentUri: "ar://x",
            contentHash: HASH_A,
            title: "Bad",
            voteId: "",
            docType: DOC_TYPE_AMENDMENT
        });
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.DocumentDoesNotExist.selector, 0, 99));
        registry.addDocument(input, refs);
    }

    function test_addDocument_emitsEvent() public {
        _createCategory("Universal Standards");

        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: 0,
            contentUri: "ar://abc",
            contentHash: HASH_A,
            title: "Article 1",
            voteId: "",
            docType: DOC_TYPE_ORIGINAL
        });
        DocumentReference[] memory refs = new DocumentReference[](0);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit DocumentAdded(0, 1, 1, "ar://abc", HASH_A, DOC_TYPE_ORIGINAL);
        registry.addDocument(input, refs);
    }

    function test_addDocument_revertsForNonAdmin() public {
        _createCategory("Universal Standards");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: 0,
            contentUri: "ar://hack",
            contentHash: HASH_A,
            title: "Unauthorized",
            voteId: "",
            docType: DOC_TYPE_ORIGINAL
        });
        DocumentReference[] memory refs = new DocumentReference[](0);
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.addDocument(input, refs);
    }

    function test_addDocument_revertsForNonexistentCategory() public {
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 99,
            documentId: 0,
            contentUri: "ar://x",
            contentHash: HASH_A,
            title: "Bad",
            voteId: "",
            docType: DOC_TYPE_ORIGINAL
        });
        DocumentReference[] memory refs = new DocumentReference[](0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.CategoryDoesNotExist.selector, 99));
        registry.addDocument(input, refs);
    }

    function test_addDocument_voteIdPreserved() public {
        _createCategory("Universal Standards");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: 0,
            contentUri: "ar://x",
            contentHash: HASH_A,
            title: "With voteId",
            voteId: "external-id-42",
            docType: DOC_TYPE_ORIGINAL
        });
        DocumentReference[] memory refs = new DocumentReference[](0);
        vm.prank(admin);
        registry.addDocument(input, refs);

        Document memory d = registry.getDocument(0, 1, 1);
        assertEq(d.voteId, "external-id-42");
    }

    // ──────────────── Read functions ─────────────────────────

    function test_getLatest_returnsMostRecentVersion() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://v1", HASH_A, "Old", DOC_TYPE_ORIGINAL);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "");
        _amendDoc(0, d1, "ar://v2", HASH_B, "New", DOC_TYPE_AMENDMENT, refs);

        Document memory latest = registry.getLatest(0, d1);
        assertEq(latest.title, "New");
        assertEq(latest.version, 2);
    }

    function test_getHistory_returnsAllVersionsInOrder() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://v1", HASH_A, "V1", DOC_TYPE_ORIGINAL);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "");
        _amendDoc(0, d1, "ar://v2", HASH_B, "V2", DOC_TYPE_AMENDMENT, refs);

        refs[0] = _ref(0, d1, 2, RELATION_AMENDS, "");
        _amendDoc(0, d1, "ar://v3", HASH_C, "V3", DOC_TYPE_AMENDMENT, refs);

        Document[] memory history = registry.getHistory(0, d1);
        assertEq(history.length, 3);
        assertEq(history[0].title, "V1");
        assertEq(history[1].title, "V2");
        assertEq(history[2].title, "V3");
    }

    function test_getDocument_revertsForNonexistentVersion() public {
        _createCategory("Universal Standards");
        _newDoc(0, "ar://x", HASH_A, "X", DOC_TYPE_ORIGINAL);
        vm.expectRevert(abi.encodeWithSelector(Registry.VersionDoesNotExist.selector, 0, 1, 5));
        registry.getDocument(0, 1, 5);
    }

    function test_getDocument_revertsForNonexistentDocument() public {
        _createCategory("Universal Standards");
        vm.expectRevert(abi.encodeWithSelector(Registry.DocumentDoesNotExist.selector, 0, 1));
        registry.getDocument(0, 1, 1);
    }

    function test_getDocumentCount_returnsZeroForNewCategory() public {
        _createCategory("Universal Standards");
        assertEq(registry.getDocumentCount(0), 0);
    }

    // ──────────────── References ─────────────────────────────

    function test_getReferences_returnsStored() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://orig", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        DocumentReference[] memory refs = new DocumentReference[](2);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "1.3");
        refs[1] = DocumentReference({
            registryAddress: address(0xCAFE),
            chainId: 1,
            categoryId: 7,
            documentId: 2,
            version: 3,
            relationType: RELATION_REFERENCES,
            targetSection: ""
        });
        _amendDoc(0, d1, "ar://amend", HASH_B, "Amendment", DOC_TYPE_AMENDMENT, refs);

        DocumentReference[] memory stored = registry.getReferences(0, d1, 2);
        assertEq(stored.length, 2);
        assertEq(stored[0].targetSection, "1.3");
        assertEq(stored[0].documentId, d1);
        assertEq(stored[0].relationType, RELATION_AMENDS);
        assertEq(stored[1].registryAddress, address(0xCAFE));
        assertEq(stored[1].chainId, 1);
        assertEq(stored[1].documentId, 2);
        assertEq(stored[1].relationType, RELATION_REFERENCES);
    }

    function test_getReferences_emptyTargetSection_wholeDocument() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://orig", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_REVISES, "");
        _amendDoc(0, d1, "ar://rev", HASH_B, "Revised", DOC_TYPE_REVISION, refs);

        DocumentReference[] memory stored = registry.getReferences(0, d1, 2);
        assertEq(stored.length, 1);
        assertEq(bytes(stored[0].targetSection).length, 0);
    }

    // ──────────────── transferAdmin ──────────────────────────

    function test_transferAdmin_transfersAndOldLosesAccess() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit AdminTransferred(admin, newAdmin);
        registry.transferAdmin(newAdmin);

        assertEq(registry.admin(), newAdmin);

        vm.prank(admin);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.addCategory("Should Fail");

        vm.prank(newAdmin);
        uint256 id = registry.addCategory("New Admin Category");
        assertEq(id, 0);
    }

    function test_transferAdmin_revertsForZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Registry.InvalidAdmin.selector);
        registry.transferAdmin(address(0));
    }

    function test_transferAdmin_revertsForNonAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.transferAdmin(stranger);
    }

    // ──────────────── Constructor ────────────────────────────

    function test_constructor_setsAdmin() public view {
        assertEq(registry.admin(), admin);
    }

    function test_constructor_revertsForZeroAddress() public {
        vm.expectRevert(Registry.InvalidAdmin.selector);
        new Registry(address(0));
    }

    // ──────────────── Multiple categories independence ───────

    function test_documentsAcrossCategoriesAreIndependent() public {
        _createCategory("Cat A");
        _createCategory("Cat B");

        _newDoc(0, "ar://a1", HASH_A, "Cat A Doc 1", DOC_TYPE_ORIGINAL);
        _newDoc(1, "ar://b1", HASH_B, "Cat B Doc 1", DOC_TYPE_ORIGINAL);
        _newDoc(0, "ar://a2", HASH_C, "Cat A Doc 2", DOC_TYPE_ORIGINAL);

        assertEq(registry.getDocumentCount(0), 2);
        assertEq(registry.getDocumentCount(1), 1);
        assertEq(registry.getDocument(0, 2, 1).title, "Cat A Doc 2");
        assertEq(registry.getDocument(1, 1, 1).title, "Cat B Doc 1");
    }

    // ──────────────── Amendment restrictions: time gate ──────

    function test_setAmendmentRestrictions_storesValuesAndEmits() public {
        _createCategory("Universal Standards");
        _newDoc(0, "ar://x", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](3);
        locked[0] = 1;
        locked[1] = 2;
        locked[2] = 5;

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit AmendmentRestrictionsUpdated(0, 1);
        registry.setAmendmentRestrictions(0, 1, 90 days, locked);

        (uint256 minTime, uint256 lastTime, uint256[] memory storedLocked) =
            registry.getAmendmentRestrictions(0, 1);
        assertEq(minTime, 90 days);
        assertEq(lastTime, block.timestamp);
        assertEq(storedLocked.length, 3);
        assertEq(storedLocked[0], 1);
        assertEq(storedLocked[2], 5);
    }

    function test_amendmentRestrictions_default_zeroAndEmpty() public {
        _createCategory("Universal Standards");
        _newDoc(0, "ar://x", HASH_A, "X", DOC_TYPE_ORIGINAL);
        (uint256 minTime, uint256 lastTime, uint256[] memory locked) =
            registry.getAmendmentRestrictions(0, 1);
        assertEq(minTime, 0);
        assertEq(lastTime, 0);
        assertEq(locked.length, 0);
    }

    function test_amendmentRestrictions_enforcesTimeWindow() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "First", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 30 days, locked);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: d1,
            contentUri: "ar://2",
            contentHash: HASH_B,
            title: "Too Soon",
            voteId: "",
            docType: DOC_TYPE_AMENDMENT
        });
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Registry.AmendmentTooSoon.selector, 0, d1, block.timestamp + 30 days)
        );
        registry.addDocument(input, refs);
    }

    function test_amendmentRestrictions_allowsAfterTimeWindow() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "First", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 30 days, locked);

        vm.warp(block.timestamp + 30 days);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "");
        (, uint256 v2) = _amendDoc(0, d1, "ar://2", HASH_B, "After Window", DOC_TYPE_AMENDMENT, refs);
        assertEq(v2, 2);
    }

    function test_setAmendmentRestrictions_revertsForNonAdmin() public {
        _createCategory("Universal Standards");
        _newDoc(0, "ar://x", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.setAmendmentRestrictions(0, 1, 30 days, locked);
    }

    function test_setAmendmentRestrictions_revertsForNonexistentDocument() public {
        _createCategory("Universal Standards");
        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.DocumentDoesNotExist.selector, 0, 1));
        registry.setAmendmentRestrictions(0, 1, 30 days, locked);
    }

    // ──────────────── Section locks ──────────────────────────

    function test_sectionLock_blocksAmendmentToLockedRoot() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](1);
        locked[0] = 1;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "1");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: d1,
            contentUri: "ar://2",
            contentHash: HASH_B,
            title: "Bad",
            voteId: "",
            docType: DOC_TYPE_AMENDMENT
        });
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.SectionLocked.selector, 0, d1, 1));
        registry.addDocument(input, refs);
    }

    function test_sectionLock_cascade_subsectionResolvesToRoot() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](1);
        locked[0] = 1;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked);

        // §1.3 resolves to root 1 → blocked
        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "1.3");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: d1,
            contentUri: "ar://2",
            contentHash: HASH_B,
            title: "1.3 amendment",
            voteId: "",
            docType: DOC_TYPE_AMENDMENT
        });
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.SectionLocked.selector, 0, d1, 1));
        registry.addDocument(input, refs);
    }

    function test_sectionLock_multiTarget_anyLockedRevertsAll() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](1);
        locked[0] = 5;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "2,3,5.1");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: d1,
            contentUri: "ar://2",
            contentHash: HASH_B,
            title: "Multi",
            voteId: "",
            docType: DOC_TYPE_AMENDMENT
        });
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.SectionLocked.selector, 0, d1, 5));
        registry.addDocument(input, refs);
    }

    function test_sectionLock_unlockedSection_passes() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](1);
        locked[0] = 1;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked);

        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "2");
        (, uint256 v2) = _amendDoc(0, d1, "ar://2", HASH_B, "sec2", DOC_TYPE_AMENDMENT, refs);
        assertEq(v2, 2);
    }

    function test_sectionLock_crossRegistryRefsNotEnforced() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        // Lock §1 on local document
        uint256[] memory locked = new uint256[](1);
        locked[0] = 1;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked);

        // Reference targets a *different* registryAddress — locks not consulted
        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = DocumentReference({
            registryAddress: address(0xDEAD),
            chainId: 1,
            categoryId: 0,
            documentId: 1,
            version: 1,
            relationType: RELATION_AMENDS,
            targetSection: "1"
        });
        // New document (documentId=0) so the lock on d1 doesn't apply via amendTooSoon either
        (, uint256 v) = _addDoc(0, 0, "ar://x", HASH_B, "Cross", DOC_TYPE_AMENDMENT, refs);
        assertEq(v, 1);
    }

    // ──────────────── Hard-lock: setAmendmentRestrictions ────

    function test_hardLock_setRestrictionsAgainDuringLock_reverts() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 30 days, locked);

        // Immediately try to modify — must revert
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Registry.RestrictionsLocked.selector, 0, d1, block.timestamp + 30 days)
        );
        registry.setAmendmentRestrictions(0, d1, 1 days, locked);
    }

    function test_hardLock_cannotRemoveLockMidWindow() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](1);
        locked[0] = 1;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 365 days, locked);

        // Try to set minTime=0 to lift — must revert
        uint256[] memory empty = new uint256[](0);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Registry.RestrictionsLocked.selector, 0, d1, block.timestamp + 365 days)
        );
        registry.setAmendmentRestrictions(0, d1, 0, empty);
    }

    function test_hardLock_freshDocumentCanSetRestrictions() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        // No prior restrictions — first call must succeed
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 30 days, locked);

        (uint256 minTime,,) = registry.getAmendmentRestrictions(0, d1);
        assertEq(minTime, 30 days);
    }

    function test_hardLock_setRestrictionsAfterWindowExpires_succeeds() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 30 days, locked);

        vm.warp(block.timestamp + 30 days);

        // Window elapsed — admin can re-lock with different params
        uint256[] memory locked2 = new uint256[](2);
        locked2[0] = 1;
        locked2[1] = 4;
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 7 days, locked2);

        (uint256 minTime,, uint256[] memory stored) = registry.getAmendmentRestrictions(0, d1);
        assertEq(minTime, 7 days);
        assertEq(stored.length, 2);
        assertEq(stored[0], 1);
        assertEq(stored[1], 4);
    }

    function test_hardLock_minTimeZero_doesNotLockRestrictions() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](1);
        locked[0] = 1;
        // minTime=0 (just section locks, no time window) — restrictions must remain modifiable
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked);

        // Modify again immediately — must succeed because no active time window
        uint256[] memory locked2 = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 0, locked2);

        (,, uint256[] memory stored) = registry.getAmendmentRestrictions(0, d1);
        assertEq(stored.length, 0);
    }

    function test_hardLock_addDocumentDuringLockReverts_andRestrictionsStillLocked() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "X", DOC_TYPE_ORIGINAL);

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, d1, 365 days, locked);

        // amendment fails AmendmentTooSoon
        DocumentReference[] memory refs = new DocumentReference[](1);
        refs[0] = _ref(0, d1, 1, RELATION_AMENDS, "");
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            documentId: d1,
            contentUri: "ar://2",
            contentHash: HASH_B,
            title: "Try",
            voteId: "",
            docType: DOC_TYPE_AMENDMENT
        });
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Registry.AmendmentTooSoon.selector, 0, d1, block.timestamp + 365 days)
        );
        registry.addDocument(input, refs);

        // and admin still cannot self-rescue
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Registry.RestrictionsLocked.selector, 0, d1, block.timestamp + 365 days)
        );
        registry.setAmendmentRestrictions(0, d1, 0, locked);
    }

    // ──────────────── IDocumentRegistry conformance ──────────

    function test_iDocumentRegistry_conformance() public {
        _createCategory("Universal Standards");
        (uint256 d1,) = _newDoc(0, "ar://1", HASH_A, "Original", DOC_TYPE_ORIGINAL);

        IDocumentRegistry iface = IDocumentRegistry(address(registry));

        Document memory doc = iface.getDocument(0, d1, 1);
        assertEq(doc.contentUri, "ar://1");

        Document[] memory history = iface.getHistory(0, d1);
        assertEq(history.length, 1);

        DocumentReference[] memory refs = iface.getReferences(0, d1, 1);
        assertEq(refs.length, 0);
    }

    // ──────────────── Fuzz ──────────────────────────────────

    function testFuzz_addDocument_arbitraryDocType(uint8 docType) public {
        _createCategory("Test");
        (uint256 d, uint256 v) = _newDoc(0, "ar://fuzz", HASH_A, "Fuzz", docType);
        assertEq(registry.getDocument(0, d, v).docType, docType);
    }

    function testFuzz_addCategory_arbitraryName(string calldata name) public {
        vm.prank(admin);
        uint256 id = registry.addCategory(name);
        assertEq(registry.categoryNames(id), name);
    }
}
