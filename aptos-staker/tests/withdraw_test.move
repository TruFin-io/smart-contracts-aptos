#[test_only]
module publisher::withdraw_test{
    use std::signer;
    use std::vector;

    use aptos_framework::delegation_pool;
    use aptos_framework::event;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::stake;
    use aptos_framework::primary_fungible_store;

    // smart contracts
    use publisher::staker::{Self, stake};
    use publisher::truAPT;

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::time;
    use publisher::setup_test_delegation_pool;

    // Test that a user can withdraw their entire stake after the unlock period has passed
    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_entire_stake(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(julia, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();  

        // user withdraws
        staker::withdraw(julia, nonce);
        assert!(coin::balance<AptosCoin>(signer::address_of(julia)) >= deposit_amount, 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_large_amounts(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        
        // accrue a lot of rewards to test overflow
        let i = 0;
        while (i < 500){
            delegation_pool::end_aptos_epoch();
            i = i + 1;
        };

        // user submits unlock request
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw);
        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();  

        // user withdraws
        staker::withdraw(alice, nonce);
        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) >= max_withdraw, 0);
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327692, location=staker)]
    public entry fun test_user_unlocks_and_withdraws_within_same_epoch_fails(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(julia, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        // no time passes

        // user withdraws
        staker::withdraw(julia, nonce); // fails with EWITHDRAW_NOT_READY
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327692, location=staker)]
    public entry fun test_user_unlocks_and_withdraws_after_one_epoch_fails(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(julia, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        delegation_pool::end_aptos_epoch();

        // user withdraws
        staker::withdraw(julia, nonce); // fails with EWITHDRAW_NOT_READY
    }


    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327690, location=staker)]
    public entry fun test_user_withdraws_with_incorrect_nonce_fails(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, tiff, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(tiff, deposit_amount);
        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(tiff, deposit_amount);
        let nonce = staker::latest_unlock_nonce();
        
        staker::unlock(julia, deposit_amount);

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(julia, nonce); // fails with ESENDER_MUST_BE_RECEIVER
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65547, location=staker)]
    public entry fun test_user_withdraws_entire_stake_twice_fails(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(julia, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(julia, nonce);
    
        staker::withdraw(julia, nonce); // fails with EINVALID_NONCE
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_multiple_users_withdraw_entire_stake(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, tiff, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(julia, deposit_amount);
        stake(tiff, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(tiff, deposit_amount);
        let first_nonce = staker::latest_unlock_nonce();
        staker::unlock(julia, deposit_amount);
        let second_nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(julia, second_nonce);
        staker::withdraw(tiff, first_nonce);
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_users_unlock_in_different_epochs_and_withdraw_in_same_epoch(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, tiff, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);

        // user stakes
        stake(julia, deposit_amount);
        stake(tiff, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(tiff, deposit_amount);

        let first_nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // check staker balance before 2nd unlock
        let apt_balance_before_second_unlock = coin::balance<AptosCoin>(signer::address_of(resource_account));
        // 2nd unlock
        staker::unlock(julia, deposit_amount);
        // assert that the first unlock amount is already withdrawn
        let apt_balance_after_second_unlock = coin::balance<AptosCoin>(signer::address_of(resource_account));
        assert!(apt_balance_after_second_unlock > (apt_balance_before_second_unlock + deposit_amount), 0);

        let second_nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(julia, second_nonce);
        staker::withdraw(tiff, first_nonce);
        assert!(coin::balance<AptosCoin>(signer::address_of(julia)) >= deposit_amount, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(tiff)) >= deposit_amount, 0);
    }

   
    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_users_unlock_and_withdraw_in_different_epochs(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, tiff, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);

        // user stakes
        stake(julia, deposit_amount);
        stake(tiff, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(tiff, deposit_amount);

        let first_nonce = staker::latest_unlock_nonce();
        
        // time passes
        time::move_olc_and_epoch_forward();

        // check staker balance before 2nd unlock
        let apt_balance_before_second_unlock = coin::balance<AptosCoin>(signer::address_of(resource_account));
        // 2nd unlock
        staker::unlock(julia, deposit_amount);
        // assert that the first unlock amount is already withdrawn
        let apt_balance_after_second_unlock = coin::balance<AptosCoin>(signer::address_of(resource_account));
        assert!(apt_balance_after_second_unlock > (apt_balance_before_second_unlock + deposit_amount), 0);

        let second_nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(julia, second_nonce);

        // time passes
        time::move_olc_and_epoch_forward();

        staker::withdraw(tiff, first_nonce);
        assert!(coin::balance<AptosCoin>(signer::address_of(tiff)) >= deposit_amount, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_withdraw_from_pool_with_inactive_state(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
       
        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool_2);

        // stake APT
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);

        // leave validator set
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();
        
        // unlock from inactive pool
        staker::unlock_from_specific_pool(alice, deposit_amount, pool_2);
        let nonce = staker::latest_unlock_nonce();
        
        // time passes
        time::move_olc_and_epoch_forward();
        
        // withdraw from inactive pool
        staker::withdraw(alice, nonce);

        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) >= deposit_amount, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_users_obtains_TruAPT_on_secondary_market_and_withdraws_associated_funds(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::prepare_account(bob);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
       
        delegation_pool::end_aptos_epoch();

        // TruAPT balance alice 
        let alice_addr = signer::address_of(alice);
        let alice_balance = truAPT::balance_of(alice_addr);

        primary_fungible_store::transfer(alice, truAPT::get_metadata(), signer::address_of(bob), alice_balance);

        // user submits unlock request
        staker::unlock(bob, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(bob, nonce);
        assert!(coin::balance<AptosCoin>(signer::address_of(bob)) >= deposit_amount, 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_is_claimable(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount);
        let nonce = staker::latest_unlock_nonce();
        delegation_pool::end_aptos_epoch();

        // olc should not have passed yet so is_claimable should return false
        assert!(!staker::is_claimable(nonce), 0);

        // time passes
        time::move_olc_and_epoch_forward();

        // now is_claimable should return true
        assert!(staker::is_claimable(nonce), 0);

        // user should be able to withdraw
        staker::withdraw(alice, nonce);
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, validator_2=@0xABC01, whitelist=@whitelist)]
    public entry fun test_is_claimable_from_inactive_validator(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
       
        // initialise additional delegation pool
        setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        staker::stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // leave validator set with default pool
        stake::leave_validator_set(validator, pool);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount);
        let nonce = staker::latest_unlock_nonce();
        delegation_pool::end_aptos_epoch();

        // olc should not have passed yet so is_claimable should return false
        assert!(!staker::is_claimable(nonce), 0);

        // time passes
        time::move_olc_and_epoch_forward();

        // now is_claimable should return true
        assert!(staker::is_claimable(nonce), 0);

        // user should be able to withdraw
        staker::withdraw(alice, nonce);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, 
    src=@src_account)]
    #[expected_failure(abort_code=65547, location=staker)]
    public entry fun test_is_claimable_fails_with_invalid_nonce(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) { 
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // call is_claimable with an invalid nonce
        staker::is_claimable(5); // fails with EINVALID_NONCE
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327692, location=staker)]
    public entry fun test_withdraw_fails_when_unlock_not_claimable(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount);
        let nonce = staker::latest_unlock_nonce();
        delegation_pool::end_aptos_epoch();

        // olc should not have passed yet so is_claimable should return false
        assert!(!staker::is_claimable(nonce), 0);

        // user attempts to withdraw
        staker::withdraw(alice, nonce); //fails with EWITHDRAW_NOT_READY
    }

// ____________________ max_withdraw() related withdraw tests  _______________________

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_withdraw_max_withdraw_amount_immediately_after_deposit(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        let alice_addr = signer::address_of(alice);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();

        let max_withdraw = staker::max_withdraw(alice_addr);
        staker::unlock(alice, max_withdraw);

        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(alice, nonce);
        
        assert!(truAPT::balance_of(alice_addr) == 0, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65544, location=staker)]
    public entry fun test_cannot_withdraw_max_withdraw_plus_one_immediately_after_deposit(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();

        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        let max_withdraw_plus_one = max_withdraw + 1;

        staker::unlock(alice, max_withdraw_plus_one);

        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(alice, nonce); // fails with EINSUFFICIENT_BALANCE
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_withdraw_max_withdraw_amount_after_accruing_rewards(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        let alice_addr = signer::address_of(alice);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();
        let max_withdraw_before = staker::max_withdraw(alice_addr);

        // time passes
        time::move_olc_and_epoch_forward();

        // get max withdraw amount
        let max_withdraw = staker::max_withdraw(alice_addr);
        assert!(max_withdraw > max_withdraw_before, 0);

        staker::unlock(alice, max_withdraw);

        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(alice, nonce);
        assert!(truAPT::balance_of(alice_addr) == 0, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65544, location=staker)]
    public entry fun test_cannot_withdraw_max_withdraw_plus_one_after_accruing_rewards(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();

        // time passes
        time::move_olc_and_epoch_forward();

        // Check min_deposit_amount was updated
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        let max_withdraw_plus_one = max_withdraw + 1;

        staker::unlock(alice, max_withdraw_plus_one);

        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        staker::withdraw(alice, nonce); // fails with EINSUFFICIENT_BALANCE
    }


    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEA3, whitelist=@whitelist)]
    public entry fun test_withdraw_from_pool_with_commission_percentage(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and default delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        
        // add a delegation pool with commission
        let pool_with_commission = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            1000 // initialize with 10% commission
        );
        staker::add_pool(admin, pool_with_commission);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);

        // add user to whitelist
        let alice_addr = signer::address_of(alice);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool_with_commission);

        // user stakes to the pool with commission
        staker::stake_to_specific_pool(alice, deposit_amount, pool_with_commission);

        // accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // unlock the max withdraw amount which includes rewards net of commission
        let withdraw_amount = staker::max_withdraw(alice_addr);
        staker::unlock_from_specific_pool(alice, withdraw_amount, pool_with_commission);

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        let nonce = staker::latest_unlock_nonce();
        staker::withdraw(alice, nonce);

        // verify withdraw_amount net of 10% commission
        let expected_reward = 10 * constants::one_apt();
        let expected_commission = expected_reward / 10; 
        let expected_fees = (expected_reward - expected_commission)/10;
        let expected_withdraw_amount = deposit_amount + expected_reward - expected_commission - expected_fees;
        assert!(withdraw_amount >= expected_withdraw_amount, 0);

        // verify the user spent the expected TruAPT and received the expected APT
        assert!(coin::balance<AptosCoin>(alice_addr) == withdraw_amount, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_withdraw_when_paused_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        staker::stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        staker::unlock(alice, deposit_amount);

        // time passes
        time::move_olc_and_epoch_forward();
        
        // pause staker
        staker::pause(admin);

        staker::withdraw(alice, 1); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_funds_can_be_withdrawn_if_validator_has_gone_inactive_during_unbonding(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add treasury deposit to pool_2 to assure the MIN_COINS_ON_SHARES_POOL
        initial_deposit(aptos_framework, whitelist, pool_2);

        // user stakes
        staker::stake_to_specific_pool(alice, deposit_amount/2, pool_2);

        time::move_olc_and_epoch_forward();

        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock_from_specific_pool(alice, max_withdraw, pool_2);
        let nonce = staker::latest_unlock_nonce();

        // check max withdraw amount has been unlocked
        let (_, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(pending_inactive == max_withdraw-1, 0);

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);

        // time passes
        time::move_olc_and_epoch_forward();

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);
        staker::withdraw(alice, nonce);

        // check MIN_COINS_ON_SHARES_POOL remain
        let (active, _, _) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active >= constants::min_coins_on_shares_pool(), 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    #[expected_failure(abort_code=327692, location=staker)]
    public entry fun test_unlocks_from_inactive_validator_cannot_be_instantly_withdrawn_from_rejoined_validator(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add treasury deposit to pool_2 to assure the MIN_COINS_ON_SHARES_POOL
        initial_deposit(aptos_framework, whitelist, pool_2);

        // user stakes
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        delegation_pool::end_aptos_epoch();

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        let observed_lockup_cycle = delegation_pool::observed_lockup_cycle(pool_2);

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // expire lockup afterwards
        time::move_olc_and_epoch_forward();

        delegation_pool::synchronize_delegation_pool(pool_2);
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);

        // unlock from inactive pool
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock_from_specific_pool(alice, max_withdraw, pool_2);
        let nonce = staker::latest_unlock_nonce();
        
        // check unlock is instantly claimable
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);
        assert!(staker::is_claimable(nonce) == true, 0);

        // re-join validator set with pool_2
        stake::join_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        // now withdrawal is no longer claimable
        staker::withdraw(alice, nonce); // EWITHDRAWAL_NOT_READY
    }


    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_unlocks_from_inactive_validator_can_be_withdrawn_from_rejoined_validator_after_one_olc(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add treasury deposit to pool_2 to assure the MIN_COINS_ON_SHARES_POOL
        initial_deposit(aptos_framework, whitelist, pool_2);

        // user stakes
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        delegation_pool::end_aptos_epoch();

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        let observed_lockup_cycle = delegation_pool::observed_lockup_cycle(pool_2);

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // expire lockup afterwards
        time::move_olc_and_epoch_forward();

        delegation_pool::synchronize_delegation_pool(pool_2);
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);

        // unlock from inactive pool
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock_from_specific_pool(alice, max_withdraw, pool_2);
        let nonce = staker::latest_unlock_nonce();
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);
        assert!(staker::is_claimable(nonce) == true, 0);

        // re-join validator set with pool_2
        stake::join_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        // wait one OLC
        time::move_olc_and_epoch_forward();

        staker::withdraw(alice, nonce);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    #[expected_failure(abort_code=327692, location=staker)]
    public entry fun test_unlocks_from_active_validator_can_be_withdrawn_from_rejoined_validator_after_one_olc(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add treasury deposit to pool_2 to assure the MIN_COINS_ON_SHARES_POOL
        initial_deposit(aptos_framework, whitelist, pool_2);

        // user stakes
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        delegation_pool::end_aptos_epoch();

        // unlock from active pool
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock_from_specific_pool(alice, max_withdraw, pool_2);
        let nonce = staker::latest_unlock_nonce();
        assert!(staker::is_claimable(nonce) == false, 0);

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        let observed_lockup_cycle = delegation_pool::observed_lockup_cycle(pool_2);

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // expire lockup afterwards
        time::move_olc_and_epoch_forward();

        delegation_pool::synchronize_delegation_pool(pool_2);
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);

        // re-join validator set with pool_2
        stake::join_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        staker::withdraw(alice, nonce); // EWITHDRAWAL_NOT_READY
    }

//  _____________________________ Event Emission Tests _____________________________
    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_WithdrawalClaimedEvent_emitted(
        julia: &signer,
        tiff: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        
        let deposit_amount = 10_000 * constants::one_apt();

        // setup whitelisted user with funds
        let user_addr = signer::address_of(julia);
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(julia, deposit_amount);

        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(julia, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();
        
        // action that emits event
        staker::withdraw(julia, nonce);

        // assert number of emitted events
        let withdraw_events = event::emitted_events<staker::WithdrawalClaimedEvent>();
        assert!(vector::length(&withdraw_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_WithdrawalClaimedEvent(user_addr, deposit_amount, nonce);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
}