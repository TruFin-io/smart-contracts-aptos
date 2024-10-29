#[test_only]
module publisher::truAPT_integration_test{
    use publisher::staker;
    use publisher::truAPT;
    use publisher::setup_test_staker;

    #[test(admin = @default_admin, resource_account = @publisher, src = @src_account)]
    public entry fun test_staker_initializes_truAPT(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
        let (_, _, _, _, _, _, truAPT, _) = staker::staker_info(); 
        let asset = truAPT::get_metadata();
        
        assert!(asset == truAPT, 0);
    }
}