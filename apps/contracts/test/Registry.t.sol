// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";

contract RegistryTest is Test {
    Registry registry;

    address admin = makeAddr("admin");
    address stranger = makeAddr("stranger");
    address newAdmin = makeAddr("newAdmin");

    bytes32 constant HASH_A = keccak256("document-a");
    bytes32 constant HASH_B = keccak256("document-b");
    bytes32 constant HASH_C = keccak256("document-c");

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

    function setUp() public {
        registry = new Registry(admin);
    }

    // ──────────────── Helpers ────────────────────────────────

    function _createCategory(string memory name) internal returns (uint256) {
        vm.prank(admin);
        return registry.addCategory(name);
    }

    function _addDocument(
        uint256 categoryId,
        string memory arweaveTxId,
        bytes32 contentHash,
        string memory title,
        uint8 docType
    ) internal returns (uint256) {
        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](0);
        return _addDocumentWithRefs(categoryId, arweaveTxId, contentHash, title, docType, refs);
    }

    function _addDocumentWithRefs(
        uint256 categoryId,
        string memory arweaveTxId,
        bytes32 contentHash,
        string memory title,
        uint8 docType,
        Registry.ExternalReference[] memory refs
    ) internal returns (uint256) {
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: categoryId,
            arweaveTxId: arweaveTxId,
            contentHash: contentHash,
            title: title,
            docType: docType
        });
        vm.prank(admin);
        return registry.addDocument(input, refs);
    }

    // ──────────────── Scenario 1: addCategory ───────────────

    function test_addCategory_createsWithSequentialId() public {
        uint256 id0 = _createCategory("Constitutional Law");
        uint256 id1 = _createCategory("Trade Regulations");

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(registry.categoryCount(), 2);
        assertEq(registry.categoryNames(0), "Constitutional Law");
        assertEq(registry.categoryNames(1), "Trade Regulations");
    }

    function test_addCategory_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit CategoryAdded(0, "Constitutional Law");
        registry.addCategory("Constitutional Law");
    }

    // ──────────────── Scenario 2: addDocument ───────────────

    function test_addDocument_storesAllFields() public {
        _createCategory("Constitutional Law");
        uint256 version = _addDocument(0, "tx_abc123", HASH_A, "Article 1", 0);

        assertEq(version, 1);

        Registry.Document memory doc = registry.getDocument(0, 1);
        assertEq(doc.arweaveTxId, "tx_abc123");
        assertEq(doc.contentHash, HASH_A);
        assertEq(doc.title, "Article 1");
        assertEq(doc.version, 1);
        assertEq(doc.timestamp, block.timestamp);
        assertEq(doc.docType, 0);
    }

    function test_addDocument_emitsEvent() public {
        _createCategory("Constitutional Law");

        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            arweaveTxId: "tx_abc123",
            contentHash: HASH_A,
            title: "Article 1",
            docType: 0
        });
        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](0);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit DocumentRegistered(0, 1, "tx_abc123", HASH_A, 0);
        registry.addDocument(input, refs);
    }

    // ──────────────── Scenario 3: Version auto-increment ────

    function test_addDocument_autoIncrementsVersion() public {
        _createCategory("Constitutional Law");

        uint256 v1 = _addDocument(0, "tx_1", HASH_A, "Version 1", 0);
        uint256 v2 = _addDocument(0, "tx_2", HASH_B, "Version 2", 0);

        assertEq(v1, 1);
        assertEq(v2, 2);
        assertEq(registry.getVersionCount(0), 2);

        assertEq(registry.getDocument(0, 1).title, "Version 1");
        assertEq(registry.getDocument(0, 2).title, "Version 2");
    }

    // ──────────────── Scenario 4: getDocument ───────────────

    function test_getDocument_returnsCorrectVersion() public {
        _createCategory("Trade Regulations");

        _addDocument(0, "tx_1", HASH_A, "Draft", 0);
        _addDocument(0, "tx_2", HASH_B, "Final", 0);

        Registry.Document memory draft = registry.getDocument(0, 1);
        Registry.Document memory final_ = registry.getDocument(0, 2);

        assertEq(draft.title, "Draft");
        assertEq(final_.title, "Final");
    }

    function test_getDocument_revertsForNonexistentCategory() public {
        vm.expectRevert(abi.encodeWithSelector(Registry.CategoryDoesNotExist.selector, 99));
        registry.getDocument(99, 1);
    }

    function test_getDocument_revertsForNonexistentVersion() public {
        _createCategory("Empty");

        vm.expectRevert(abi.encodeWithSelector(Registry.VersionDoesNotExist.selector, 0, 5));
        registry.getDocument(0, 5);
    }

    function test_getDocument_revertsForVersionZero() public {
        _createCategory("Empty");

        vm.expectRevert(abi.encodeWithSelector(Registry.VersionDoesNotExist.selector, 0, 0));
        registry.getDocument(0, 0);
    }

    // ──────────────── Scenario 5: getLatest ─────────────────

    function test_getLatest_returnsMostRecentVersion() public {
        _createCategory("Constitutional Law");

        _addDocument(0, "tx_old", HASH_A, "Old", 0);
        _addDocument(0, "tx_new", HASH_B, "New", 0);

        Registry.Document memory latest = registry.getLatest(0);
        assertEq(latest.title, "New");
        assertEq(latest.version, 2);
    }

    function test_getLatest_revertsForEmptyCategory() public {
        _createCategory("Empty");

        vm.expectRevert(abi.encodeWithSelector(Registry.VersionDoesNotExist.selector, 0, 0));
        registry.getLatest(0);
    }

    // ──────────────── Scenario 6: getHistory ────────────────

    function test_getHistory_returnsAllVersionsInOrder() public {
        _createCategory("Constitutional Law");

        _addDocument(0, "tx_1", HASH_A, "V1", 0);
        _addDocument(0, "tx_2", HASH_B, "V2", 0);
        _addDocument(0, "tx_3", HASH_C, "V3", 0);

        Registry.Document[] memory history = registry.getHistory(0);

        assertEq(history.length, 3);
        assertEq(history[0].title, "V1");
        assertEq(history[0].version, 1);
        assertEq(history[1].title, "V2");
        assertEq(history[1].version, 2);
        assertEq(history[2].title, "V3");
        assertEq(history[2].version, 3);
    }

    function test_getHistory_returnsEmptyForCategoryWithNoDocuments() public {
        _createCategory("Empty");

        Registry.Document[] memory history = registry.getHistory(0);
        assertEq(history.length, 0);
    }

    // ──────────────── Scenario 7: getReferences ─────────────

    function test_getReferences_returnsStoredReferences() public {
        _createCategory("Constitutional Law");

        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](2);
        refs[0] = Registry.ExternalReference({
            registryAddress: address(0xBEEF),
            chainId: block.chainid,
            categoryId: 0,
            version: 1,
            relationType: 0, // GOVERNS
            targetSection: ""
        });
        refs[1] = Registry.ExternalReference({
            registryAddress: address(0xCAFE),
            chainId: block.chainid,
            categoryId: 2,
            version: 3,
            relationType: 4, // REFERENCES
            targetSection: ""
        });

        _addDocumentWithRefs(0, "tx_ref", HASH_A, "With Refs", 0, refs);

        Registry.ExternalReference[] memory stored = registry.getReferences(0, 1);
        assertEq(stored.length, 2);
        assertEq(stored[0].registryAddress, address(0xBEEF));
        assertEq(stored[0].categoryId, 0);
        assertEq(stored[0].version, 1);
        assertEq(stored[0].relationType, 0);
        assertEq(bytes(stored[0].targetSection).length, 0);
        assertEq(stored[1].registryAddress, address(0xCAFE));
        assertEq(stored[1].relationType, 4);
        assertEq(bytes(stored[1].targetSection).length, 0);
    }

    function test_getReferences_returnsEmptyWhenNone() public {
        _createCategory("Constitutional Law");
        _addDocument(0, "tx_1", HASH_A, "No Refs", 0);

        Registry.ExternalReference[] memory refs = registry.getReferences(0, 1);
        assertEq(refs.length, 0);
    }

    // ──────────────── Scenario 10–11: targetSection ────────────

    function test_getReferences_storesTargetSection() public {
        _createCategory("Constitutional Law");
        _addDocument(0, "tx_orig", HASH_A, "Original Law", 0);

        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](1);
        refs[0] = Registry.ExternalReference({
            registryAddress: address(registry),
            chainId: block.chainid,
            categoryId: 0,
            version: 1,
            relationType: 0, // AMENDS
            targetSection: "1.3"
        });

        _addDocumentWithRefs(0, "tx_amend", HASH_B, "Amendment to 1.3", 1, refs);

        Registry.ExternalReference[] memory stored = registry.getReferences(0, 2);
        assertEq(stored.length, 1);
        assertEq(stored[0].targetSection, "1.3");
        assertEq(stored[0].relationType, 0);
        assertEq(stored[0].version, 1);
    }

    function test_getReferences_emptyTargetSectionForWholeDocument() public {
        _createCategory("Constitutional Law");
        _addDocument(0, "tx_orig", HASH_A, "Original Law", 0);

        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](1);
        refs[0] = Registry.ExternalReference({
            registryAddress: address(registry),
            chainId: block.chainid,
            categoryId: 0,
            version: 1,
            relationType: 1, // REVISES
            targetSection: ""
        });

        _addDocumentWithRefs(0, "tx_revise", HASH_B, "Full Revision", 2, refs);

        Registry.ExternalReference[] memory stored = registry.getReferences(0, 2);
        assertEq(stored.length, 1);
        assertEq(bytes(stored[0].targetSection).length, 0);
        assertEq(stored[0].relationType, 1);
    }

    function test_getReferences_variousSectionFormats() public {
        _createCategory("Constitutional Law");
        _addDocument(0, "tx_orig", HASH_A, "Original Law", 0);

        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](3);
        refs[0] = Registry.ExternalReference({
            registryAddress: address(registry),
            chainId: block.chainid,
            categoryId: 0,
            version: 1,
            relationType: 0,
            targetSection: "1"
        });
        refs[1] = Registry.ExternalReference({
            registryAddress: address(registry),
            chainId: block.chainid,
            categoryId: 0,
            version: 1,
            relationType: 0,
            targetSection: "1.3"
        });
        refs[2] = Registry.ExternalReference({
            registryAddress: address(registry),
            chainId: block.chainid,
            categoryId: 0,
            version: 1,
            relationType: 0,
            targetSection: "2.1.A"
        });

        _addDocumentWithRefs(0, "tx_multi", HASH_C, "Multi-section Amendment", 1, refs);

        Registry.ExternalReference[] memory stored = registry.getReferences(0, 2);
        assertEq(stored.length, 3);
        assertEq(stored[0].targetSection, "1");
        assertEq(stored[1].targetSection, "1.3");
        assertEq(stored[2].targetSection, "2.1.A");
    }

    // ──────────────── Scenario 8: transferAdmin ─────────────

    function test_transferAdmin_transfersAdmin() public {
        vm.prank(admin);
        registry.transferAdmin(newAdmin);

        assertEq(registry.admin(), newAdmin);
    }

    function test_transferAdmin_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit AdminTransferred(admin, newAdmin);
        registry.transferAdmin(newAdmin);
    }

    function test_transferAdmin_oldAdminLosesAccess() public {
        vm.prank(admin);
        registry.transferAdmin(newAdmin);

        vm.prank(admin);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.addCategory("Should Fail");
    }

    function test_transferAdmin_newAdminCanWrite() public {
        vm.prank(admin);
        registry.transferAdmin(newAdmin);

        vm.prank(newAdmin);
        uint256 id = registry.addCategory("New Admin Category");
        assertEq(id, 0);
    }

    function test_transferAdmin_revertsForZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Registry.InvalidAdmin.selector);
        registry.transferAdmin(address(0));
    }

    // ──────────────── Scenario 9: Admin-only writes ─────────

    function test_addCategory_revertsForNonAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.addCategory("Unauthorized");
    }

    function test_addDocument_revertsForNonAdmin() public {
        _createCategory("Constitutional Law");

        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            arweaveTxId: "tx_hack",
            contentHash: HASH_A,
            title: "Unauthorized",
            docType: 0
        });
        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](0);

        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.addDocument(input, refs);
    }

    function test_transferAdmin_revertsForNonAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.transferAdmin(stranger);
    }

    function test_addDocument_revertsForNonexistentCategory() public {
        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 99,
            arweaveTxId: "tx_1",
            contentHash: HASH_A,
            title: "Bad Category",
            docType: 0
        });
        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Registry.CategoryDoesNotExist.selector, 99));
        registry.addDocument(input, refs);
    }

    // ──────────────── Constructor ───────────────────────────

    function test_constructor_setsAdmin() public view {
        assertEq(registry.admin(), admin);
    }

    function test_constructor_revertsForZeroAddress() public {
        vm.expectRevert(Registry.InvalidAdmin.selector);
        new Registry(address(0));
    }

    // ──────────────── Multiple Categories ───────────────────

    function test_documentsAcrossCategoriesAreIndependent() public {
        _createCategory("Category A");
        _createCategory("Category B");

        _addDocument(0, "tx_a1", HASH_A, "Cat A Doc 1", 0);
        _addDocument(1, "tx_b1", HASH_B, "Cat B Doc 1", 0);
        _addDocument(0, "tx_a2", HASH_C, "Cat A Doc 2", 0);

        assertEq(registry.getVersionCount(0), 2);
        assertEq(registry.getVersionCount(1), 1);
        assertEq(registry.getDocument(0, 2).title, "Cat A Doc 2");
        assertEq(registry.getDocument(1, 1).title, "Cat B Doc 1");
    }

    // ──────────────── Amendment Restrictions ────────────────

    function test_amendmentRestrictions_defaultToZero() public {
        _createCategory("Constitutional Law");

        (uint256 minTime, uint256 lastTime, uint256[] memory locked, uint256 threshold) =
            registry.getAmendmentRestrictions(0);

        assertEq(minTime, 0);
        assertEq(lastTime, 0);
        assertEq(locked.length, 0);
        assertEq(threshold, 0);
    }

    function test_setAmendmentRestrictions_storesValues() public {
        _createCategory("Constitutional Law");

        uint256[] memory locked = new uint256[](3);
        locked[0] = 1;
        locked[1] = 2;
        locked[2] = 5;

        vm.prank(admin);
        registry.setAmendmentRestrictions(0, 90 days, locked, 90);

        (uint256 minTime,, uint256[] memory storedLocked, uint256 threshold) =
            registry.getAmendmentRestrictions(0);

        assertEq(minTime, 90 days);
        assertEq(threshold, 90);
        assertEq(storedLocked.length, 3);
        assertEq(storedLocked[0], 1);
        assertEq(storedLocked[1], 2);
        assertEq(storedLocked[2], 5);
    }

    function test_setAmendmentRestrictions_emitsEvent() public {
        _createCategory("Constitutional Law");

        uint256[] memory locked = new uint256[](0);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit AmendmentRestrictionsUpdated(0);
        registry.setAmendmentRestrictions(0, 30 days, locked, 75);
    }

    function test_amendmentRestrictions_enforcesTimeWindow() public {
        _createCategory("Constitutional Law");

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, 30 days, locked, 0);

        _addDocument(0, "tx_1", HASH_A, "First", 0);

        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            arweaveTxId: "tx_2",
            contentHash: HASH_B,
            title: "Too Soon",
            docType: 0
        });
        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](0);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Registry.AmendmentTooSoon.selector, 0, block.timestamp + 30 days)
        );
        registry.addDocument(input, refs);
    }

    function test_amendmentRestrictions_allowsAfterTimeWindow() public {
        _createCategory("Constitutional Law");

        uint256[] memory locked = new uint256[](0);
        vm.prank(admin);
        registry.setAmendmentRestrictions(0, 30 days, locked, 0);

        _addDocument(0, "tx_1", HASH_A, "First", 0);

        vm.warp(block.timestamp + 30 days);

        uint256 v2 = _addDocument(0, "tx_2", HASH_B, "After Window", 0);
        assertEq(v2, 2);
    }

    function test_setAmendmentRestrictions_revertsForNonAdmin() public {
        _createCategory("Constitutional Law");

        uint256[] memory locked = new uint256[](0);
        vm.prank(stranger);
        vm.expectRevert(Registry.NotAdmin.selector);
        registry.setAmendmentRestrictions(0, 30 days, locked, 0);
    }

    // ──────────────── Gas Estimation ────────────────────────

    function test_gas_addCategory() public {
        vm.prank(admin);
        uint256 gasBefore = gasleft();
        registry.addCategory("Constitutional Law");
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas used for addCategory", gasUsed);
    }

    function test_gas_addDocument() public {
        _createCategory("Constitutional Law");

        Registry.DocumentInput memory input = Registry.DocumentInput({
            categoryId: 0,
            arweaveTxId: "tx_abc123xyz",
            contentHash: HASH_A,
            title: "Article 1: Fundamental Rights",
            docType: 0
        });
        Registry.ExternalReference[] memory refs = new Registry.ExternalReference[](0);

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        registry.addDocument(input, refs);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas used for addDocument", gasUsed);
    }

    // ──────────────── Fuzz Tests ────────────────────────────

    function testFuzz_addDocument_arbitraryDocType(uint8 docType) public {
        _createCategory("Test");
        uint256 v = _addDocument(0, "tx_fuzz", HASH_A, "Fuzz", docType);

        assertEq(registry.getDocument(0, v).docType, docType);
    }

    function testFuzz_addCategory_arbitraryName(string calldata name) public {
        vm.prank(admin);
        uint256 id = registry.addCategory(name);

        assertEq(registry.categoryNames(id), name);
    }
}
