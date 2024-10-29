#[test_only]
module publisher::multi_validator_test{
    use std::vector;

    use aptos_framework::event;

    // smart contracts
    use publisher::staker::{Self, add_pool, test_DelegationPoolAddedEvent, test_pool};

    // test modules
    use publisher::setup_test_staker;
    use publisher::setup_test_delegation_pool;

    // constants
    const POOL_ENABLED: u8 = 1;
    const POOL_DISABLED: u8 = 2;

    //  _____________________________ User Function Tests _____________________________
    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_add_new_delegation_pool(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);
        let new_pool = setup_test_delegation_pool::create_basic_pool(admin);

        // add a new delegation pool
        add_pool(admin, new_pool);

        let(pool_address, epoch, fees, state) = test_pool(new_pool);
        assert!(pool_address == new_pool, 0);
        assert!(epoch == 0, 0);
        assert!(fees == 0, 0);
        assert!(state == POOL_ENABLED, 0);
    }

    // Failures
    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_add_new_delegation_pool_fails_with_zero_address(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // add zero address as a new delegation pool
        add_pool(admin, @0x0);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=524301, location=staker)]
    public entry fun test_add_new_delegation_pool_twice_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        // add the default delegation pool as a new pool
        add_pool(admin, pool);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_add_new_delegation_pool_fails_when_not_called_by_admin(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // add a new delegation pool with a non-admin account
        add_pool(src, @0x111);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_enable_delegation_pool(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);
        staker::disable_pool(admin, pool);

        // enable the delegation pool
        staker::enable_pool(admin, pool);

        // assert event contents
        let(_, _, _, state) = test_pool(pool);
        assert!(state == POOL_ENABLED, 0);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=196624, location=staker)]
    public entry fun test_enable_delegation_pool_fails_when_already_enabled(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);

        // enable the delegation pool
        staker::enable_pool(admin, pool);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_enable_delegation_pool_fails_when_not_called_by_admin(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);

        // enable the delegation pool
        staker::enable_pool(src, pool);
    }


    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_enable_delegation_pool_fails_with_invalid_pool_address(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);

        // enable the delegation pool
        staker::enable_pool(admin, @0x122);
    }
    
    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_add_delegation_pool_fails_with_invalid_pool_address(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        staker::add_pool(admin, @0x122); // EINVALID_POOL_ADDRESS
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_enable_delegation_pool_with_zero_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // fails with EZERO_ADDRESS
        staker::enable_pool(admin, @0x0);
    }

   #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_disable_delegation_pool(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);

        // enable the delegation pool
        staker::disable_pool(admin, pool);

        // assert event contents
        let(_, _, _, state) = test_pool(pool);
        assert!(state == POOL_DISABLED, 0);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_disable_delegation_pool_fails_when_not_called_by_admin(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);

        // enable the delegation pool
        staker::disable_pool(src, pool);
    }


    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_disable_delegation_pool_fails_with_invalid_pool_address(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);

        // disable the delegation pool
        staker::disable_pool(admin, @0x122);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=196623, location=staker)]
    public entry fun test_disable_delegation_pool_fails_when_already_disabled(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);
        staker::disable_pool(admin, pool);

        // enable the delegation pool
        staker::disable_pool(admin, pool);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_disable_delegation_pool_with_zero_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // fails with EZERO_ADDRESS
        staker::disable_pool(admin, @0x0);
    }

    // Event Emission

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_add_new_delegation_pool_emits_event(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);

        // add a new delegation pool
        add_pool(admin, pool);

        // assert number of emitted events
        let delegation_pool_added_event = event::emitted_events<staker::DelegationPoolAddedEvent>();
        assert!(vector::length(&delegation_pool_added_event) == 1, 0);

        // assert event contents
        let expected_event = test_DelegationPoolAddedEvent(pool);
        assert!(event::was_event_emitted(&expected_event), 0);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_enable_delegation_pool_emits_event(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);
        staker::disable_pool(admin, pool);
        // get pool state prior to change
        let(pool_address, _, _, state) = test_pool(pool);

        // enable the delegation pool
        staker::enable_pool(admin, pool);

        // assert number of emitted events
        let delegation_pool_enabled_event = event::emitted_events<staker::DelegationPoolStateChangedEvent>();
        assert!(vector::length(&delegation_pool_enabled_event) == 2, 0);

        // assert event contents
        let expected_event = staker::test_DelegationPoolStateChangedEvent(pool_address, state, POOL_ENABLED);
        assert!(event::was_event_emitted(&expected_event), 0);
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_disable_delegation_pool_emits_event(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, pool);
        
        // get pool state prior to change
        let(pool_address, _, _, state) = test_pool(pool);

        // enable the delegation pool
        staker::disable_pool(admin, pool);

        // assert number of emitted events
        let delegation_pool_enabled_event = event::emitted_events<staker::DelegationPoolStateChangedEvent>();
        assert!(vector::length(&delegation_pool_enabled_event) == 1, 0);

        // assert event contents
        let expected_event = staker::test_DelegationPoolStateChangedEvent(pool_address, state, POOL_DISABLED);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
}