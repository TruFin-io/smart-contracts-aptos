#[test_only]
module publisher::init_test {
    use std::signer;
    use std::string::{String,utf8};
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::delegation_pool;
    use aptos_framework::stake;

    // smart contracts
    use publisher::staker::{Self, test_initialize, staker_info, test_fee_precision, test_min_coins_on_share_pool};

    // test modules
    use publisher::account_setup;
    use publisher::setup_test_staker;
    use publisher::setup_test_delegation_pool;

//  _____________________________ Initializer Tests _____________________________
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_initialised(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let pool = setup_test_staker::setup(admin, resource_account, src);
       
        let (staker_name, treasury, fee, distribution_fee, min_deposit, staker_admin, _, paused) = staker_info();
        let delegation_pool = staker::default_pool();

        assert!(staker_name == utf8(b"Trufin aptos staker v1"), 0);
        assert!(treasury == @0x122, 0);
        assert!(min_deposit == 1000000000, 0); // 10 APT
        assert!(fee == 1000, 0);
        assert!(distribution_fee == 500, 0);
        assert!(staker_admin==signer::address_of(admin), 0);
        assert!(delegation_pool == pool, 0);
        assert!(paused == false, 0);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_initialising_staker_emits_event(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        
        let (staker_name, treasury, fee, distribution_fee, min_deposit, staker_admin, _, _) = staker_info();
        let delegation_pool = staker::default_pool();
               
        // assert number of emitted events
        let initialised_events = event::emitted_events<staker::StakerInitialisedEvent>();
        assert!(vector::length(&initialised_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_StakerInitialisedEvent(
            staker_name,
            treasury,
            delegation_pool,
            fee,
            distribution_fee,
            min_deposit,
            staker_admin
        );
        assert!(event::was_event_emitted(&expected_event), 0);
    }

//  _____________________________ Failure Tests _____________________________
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure (abort_code=524289, location=staker)]
    public entry fun test_initialised_twice_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let name: String = utf8(b"Trufin aptos staker v1");
        setup_test_staker::setup(admin, resource_account, src);
        staker::initialize(
            admin,
            name,
            @0x122,
            @0x111,
            10,
            10,
            100,
        );
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65538, location=staker)]
    public entry fun test_initialised_with_name_too_long_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Salut. Je suis un stakerjdfalsdjfklsjdfkdslfjkdsjflksdjfslkjsdlkfjskldfjskldfjlksdjfskldjfslkjdfksjflskjfklsdjfklsjflskjflksjflksjklsfjslkfjslkfjslkfjsl.");
        test_initialize(resource_account);
        staker::initialize(            
            admin,
            name,
            @0x122,
            @0x111,
            10,
            10,
            100);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_initialised_with_zero_treasury_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker version 0.0.1");
        test_initialize(resource_account);
        staker::initialize(            
            admin,
            name,
            @0x000,
            @0x111,
            10,
            10,
            100);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_initialised_with_zero_default_delegation_pool_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker version 0.0.1");
        test_initialize(resource_account);
        staker::initialize(            
            admin,
            name,
            @0x122,
            @0x000,
            10,
            10,
            1000000000);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_initialised_with_non_existent_default_delegation_pool_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker version 0.0.1");
        test_initialize(resource_account);
        staker::initialize(            
            admin,
            name,
            @0x122,
            @0x120,
            10,
            10,
            1000000000);
    }
    
    #[test(aptos_framework=@0x1, admin=@default_admin, resource_account=@publisher, src=@src_account, 
    validator_1=@0x393, validator_2=@0x394)]    
    #[expected_failure(abort_code=196635, location=staker)]
    public entry fun test_initialised_with_inactive_default_delegation_pool_fails(
        aptos_framework: &signer,
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer
    ) {
        account::create_account_for_test(@0x1);
        setup_test_delegation_pool::setup(aptos_framework);
       
        // initialise two pools
        let pool = setup_test_delegation_pool::create_delegation_pool(
            validator_1,
            10000000000,
            true,
            true,
            0
        );
        
        setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            10000000000,
            true,
            true,
            0
        );

        // leave validator set with first pool so it becomes inactive
        stake::leave_validator_set(validator_1, pool);
        delegation_pool::end_aptos_epoch();

        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker version 0.0.1");
        test_initialize(resource_account);
        staker::initialize(            
            admin,
            name,
            @0x122,
            pool,
            10,
            10,
            1000000000);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_initialised_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker.");
        test_initialize(resource_account);
        staker::initialize(
            src,
            name,
            @0x123,
            @0x122,
            100,
            10,
            100,
        );
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65541, location=staker)]
    public entry fun test_initialize_with_fee_too_large_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker.");
        test_initialize(resource_account);

        let max_fees = test_fee_precision();

        // fails with EFEE_TOO_LARGE
        staker::initialize(
            admin,
            name,
            @0x123,
            @0x122,
            max_fees,
            10,
            100,
        );
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65541, location=staker)]
    public entry fun test_initialize_with_dist_fee_too_large_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker.");
        test_initialize(resource_account);

        let max_dist_fees = test_fee_precision();

        // fails with EFEE_TOO_LARGE
        staker::initialize(
            admin,
            name,
            @0x123,
            @0x122,
            100,
            max_dist_fees,
            100,
        );
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65555, location=staker)]
    public entry fun test_initialize_with_min_deposit_below_min_coins_on_share_pool_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        account_setup::create_main_accounts(admin,resource_account,src);
        let name: String = utf8(b"Staker.");
        test_initialize(resource_account);

        let min_deposit = test_min_coins_on_share_pool() - 1;

        // fails with EBELOW_MIN_STAKE
        staker::initialize(
            admin,
            name,
            @0x123,
            @0x122,
            100,
            100,
            min_deposit,
        );
    }
}