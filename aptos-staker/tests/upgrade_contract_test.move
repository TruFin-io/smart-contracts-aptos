#[test_only]
module publisher::upgrade_contract_test {
    use std::vector;

    // test modules
    use publisher::setup_test_staker;
    use publisher::staker;
    
    #[test(admin=@default_admin, resource_account=@publisher, alice=@0xA11CE, src=@src_account)]    
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_upgrade_contract_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        alice: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        let metadata = vector::empty<u8>();
        let code = vector::empty<vector<u8>>();

        // fails with ENOT_ADMIN
        staker::upgrade_contract(alice, metadata, code);
    }
}