#[test_only]
module publisher::stake_test{
    use std::signer;
    use std::vector;

    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::delegation_pool; 
    use aptos_framework::event;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::stake;
    use aptos_framework::staking_config;

    // smart contracts
    use publisher::staker::{Self, staker_info, stake, share_price, share_price_scaling_factor};
    use publisher::truAPT;
    use whitelist::master_whitelist;

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::setup_test_delegation_pool;
    use publisher::time;

    //  _____________________________ User Function Tests _____________________________
    #[test(julia=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_stake_receives_apt_and_returns_truapt(
        julia: &signer,
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
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // transfer and stake APT
        stake(julia, deposit_amount);
        
        // check truAPT balance has increased
        let (_, _, _, _, _, _, truAPT_metadata, _) = staker_info();
        let new_truAPT_balance = primary_fungible_store::balance(signer::address_of(julia), truAPT_metadata); 
        assert!(new_truAPT_balance == deposit_amount, 0);

        // check that APT balance has decreased
        assert!(coin::balance<AptosCoin>(signer::address_of(julia)) == 0, 0);
    }
    
    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    #[expected_failure(abort_code=196635, location=staker)]
    public entry fun test_cannot_stake_to_inactive_pool(
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

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // stake more APT to inactive pool
        staker::stake_to_specific_pool(alice, deposit_amount/2, pool_2); // fails with EVALIDATOR_NOT_ACTIVE
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    #[expected_failure(abort_code=196635, location=staker)]
    public entry fun test_cannot_stake_to_pending_active_pool(
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
            false,   // should join validator set
            false,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // join validator so that the validator status is pending active
        stake::join_validator_set(validator_2, pool_2);
       
        // ensure pool is pending active
        assert!(stake::get_validator_state(pool_2) == constants::pending_active_validator_status(), 0);

        // stake more APT to pending active pool
        staker::stake_to_specific_pool(alice, deposit_amount/2, pool_2); // fails with EVALIDATOR_NOT_ACTIVE
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    #[expected_failure(abort_code=196635, location=staker)]
    public entry fun test_cannot_stake_to_pending_inactive_pool(
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

        // leave validator set with pool_2 but don't end epoch
        stake::leave_validator_set(validator_2, pool_2);

        // ensure pool is pending inactive
        assert!(stake::get_validator_state(pool_2) == constants::pending_inactive_validator_status(), 0);

        // stake more APT to inactive pool
        staker::stake_to_specific_pool(alice, deposit_amount/2, pool_2); // fails with EVALIDATOR_NOT_ACTIVE
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65554, location=staker)]
    public entry fun test_stake_more_than_maximum_stake_amount_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // The current maximum allowed stake is 50M. Users should not be able to deposit if their stake brings us
        // over the maximum allowed stake.
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with 51M APT
        let deposit_amount = 51000000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // keep staking and, as rewards accrue, the staker will hit its max staking amount
        let i = 0;
        while (i < 50) {
            stake(alice, 1000000 * constants::one_apt());
            delegation_pool::end_aptos_epoch();
            i = i + 1;
        }; // will eventually fail with EPOOL_AT_MAX_CAPACITY
    }
    
    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65554, location=staker)]
    public entry fun test_stake_maximum_stake_amount_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // The current maximum allowed stake is 50M. Users should not be able to deposit if their stake brings us
        // to the maximum allowed stake.
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with 51M APT
        let deposit_amount = 50000000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // Stake just below max_stake limit
        staker::stake_to_specific_pool(alice, 49000000 * constants::one_apt(), pool); // will work
        // Stake equal to max_stake limit
        staker::stake_to_specific_pool(alice, 1000000 * constants::one_apt(), pool); // will fail with EPOOL_AT_MAX_CAPACITY
    }

    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, whitelist=@whitelist)]
    #[expected_failure(abort_code=65542, location=staker)]
    public entry fun test_stake_zero_fails(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        whitelist: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // whitelist and setup user with APT
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, 10_000);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // transfer 0 tokens
        stake(julia, 0);
    }

    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher,
    src=@src_account, whitelist=@whitelist)]
    #[expected_failure(abort_code=65542, location=staker)]
    public entry fun test_stake_less_than_min_deposit_fails(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        whitelist: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // whitelist and setup user with APT
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // transfer less than our specified min_deposit amount
        stake(julia, 9 * constants::one_apt());
    }
    
    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher,
    src=@src_account, whitelist=@whitelist)]
    #[expected_failure(abort_code=327689, location=staker)]
    public entry fun test_not_whitelisted_user_stake_fails(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        whitelist: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // whitelist and setup user with APT
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, 10_000);
        master_whitelist::test_initialize(whitelist);        

        // stake 200 APT
        stake(julia, 200);
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65549, location=stake)]
    public entry fun test_user_adds_stake_fails_with_too_large_voting_power_increase_in_current_epoch(
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
        staking_config::update_voting_power_increase_limit(aptos_framework, 20);

        // whitelist and setup for withdraw
        let small_amount = 1_000 * constants::one_apt(); 
        let large_amount = 1_000_000 * constants::one_apt();

        account_setup::setup_account_and_mint_APT(aptos_framework, julia, small_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, tiff, large_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
        
        // tiff stakes
        stake(tiff, small_amount);
        
        // julia stakes
        stake(julia, large_amount);
    }

    #[test(julia=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_stake_transfers_apt_to_delegation_pool(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist setup user with APT
        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, stake_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);
    
        // get pending stake on delegation pool
        let delegation_pool = staker::default_pool();
        let (_, _, pending_stake_before, _) = delegation_pool::get_delegation_pool_stake(delegation_pool);

        // transfer and stake tokens
        stake(julia, stake_amount);

        // verify that the delegation pool received the amount staked
        let (_, _, pending_stake, _) = delegation_pool::get_delegation_pool_stake(delegation_pool);
        let amount_transferred = pending_stake - pending_stake_before;
        assert!(amount_transferred == stake_amount, 0);
    }

    #[test(julia=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_stake_mints_shares_one_stake_no_rewards_paid(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        let share_balance_before_stake = truAPT::balance_of(signer::address_of(julia));
        assert!(share_balance_before_stake == 0, 0);

        // 1st stake Shares are minted at the initial price of 1
        let first_stake = 100 * constants::one_apt();
        stake(julia, first_stake);
        delegation_pool::end_aptos_epoch();

        // Shares are minted at the initial price of 1
        let (price_num, price_denom) = share_price();
        let scaling_factor = share_price_scaling_factor();
        let price_1st_mint = ((price_num / price_denom / scaling_factor) as u64) ;
        assert!(price_1st_mint == 1, 0);
        
        let share_balance_after_stake = truAPT::balance_of(signer::address_of(julia));
        let expected_balance = first_stake * price_1st_mint;
        
        assert!(share_balance_after_stake == expected_balance, 0);
    }

    #[test(julia=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_stake_mints_shares_two_stakes_rewards_paid(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // 1st stake
        let first_stake = 100 * constants::one_apt();
        stake(julia, first_stake);

        // end 1 epoch, add stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        // Shares are minted at the initial price of 1
        let scaling_factor = share_price_scaling_factor();
        let price_1st_mint = 1;
        let expected_shares_1st_stake = first_stake * price_1st_mint;
        
        assert!(truAPT::balance_of(signer::address_of(julia)) == expected_shares_1st_stake, 0);

        // end 2 epochs, 1st stake rewards are paid out
        delegation_pool::end_aptos_epoch();

        // 2nd stake. 
        let second_stake = 200 * constants::one_apt();
        stake(julia, second_stake);

         // get share price after 2nd stake
        let (price_num, price_denom) = share_price();
        let price_scaled = scaling_factor * price_num / price_denom;

        // expected shares minted to the user at the share price when the 2nd stake was made
        let expected_shares_2nd_stake = (((second_stake as u256) * scaling_factor * scaling_factor / price_scaled) as u64);

        let share_balance_after_2nd_stake = truAPT::balance_of(signer::address_of(julia));
        let expected_balance = expected_shares_1st_stake + expected_shares_2nd_stake;

        assert!(share_balance_after_2nd_stake == expected_balance, 0);
    }

    #[test(julia=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_stake_to_specific_pool_receives_apt_and_returns_truapt(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let pool = staker::default_pool();

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);
    
        // transfer and stake APT
        staker::stake_to_specific_pool(julia, deposit_amount, pool);
        
        // check truAPT balance has increased
        let (_, _, _, _, _, _, truAPT_metadata, _) = staker_info();
        let new_truAPT_balance = primary_fungible_store::balance(signer::address_of(julia), truAPT_metadata); 
        assert!(new_truAPT_balance == deposit_amount, 0);

        // check that APT balance has decreased
        assert!(coin::balance<AptosCoin>(signer::address_of(julia)) == 0, 0);
    }
    
    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEA3, whitelist=@whitelist)]
    public entry fun test_stake_to_pool_with_commission_percentage(
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
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        
        // initialise delegation pool with commission
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            1000 // initialize with 10% commission
        );
        staker::add_pool(admin, pool_2);

        // whitelist and setup user with APT
        let deposit_amount = 10000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2 * deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
    
        // stake APT with 0 commission pool
        staker::stake(alice, deposit_amount);
        // stake APT with commission pool
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);

        // two epochs pass to accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        let(active_commission, _, _) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        let(active_no_commission, _, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        
        // check that commission has been taken from the rewards 
        assert!(active_no_commission - active_commission > constants::one_apt(), 0);
    }

    #[test(julia=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=196625, location=staker)]
    public entry fun test_stake_to_specific_pool_reverts_with_delegation_pool_disabled(
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

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);
    
        // disable delegation pool
        staker::disable_pool(admin, pool);

        // stake APT
        staker::stake_to_specific_pool(julia, deposit_amount, pool); // EPOOL_DISABLED
    }

    #[test(julia=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_stake_to_specific_pool_reverts_with_invalid_pool_address(
        julia: &signer,
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
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // stake APT
        let pool = setup_test_delegation_pool::create_basic_pool(src);
        staker::stake_to_specific_pool(julia, deposit_amount, pool); // EINVALID_POOL_ADDRESS
    }
   
    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_stake_when_paused_fails(
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

        // pause pool
        staker::pause(admin);

        staker::stake(alice, deposit_amount); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_stake_to_specific_pool_when_paused_fails(
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
        let pool = setup_test_delegation_pool::create_basic_pool(src);

        // pause pool
        staker::pause(admin);

        staker::stake_to_specific_pool(alice, deposit_amount, pool); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1, whitelist=@whitelist)]
    #[expected_failure(abort_code=196635, location=staker)]
    public entry fun test_stake_to_inactive_pool_fails(
        admin: &signer,
        alice: &signer,
        whitelist: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);

        staker::add_pool(admin, pool);

        stake::leave_validator_set(admin, pool);

        staker::stake_to_specific_pool(alice, 10*constants::one_apt(), pool); // aborts with EVALIDATOR_NOT_ACTIVE
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_stake_to_rejoined_validator(
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

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        let observed_lockup_cycle = delegation_pool::observed_lockup_cycle(pool_2);

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // expire lockup afterwards
        time::move_olc_and_epoch_forward();

        delegation_pool::synchronize_delegation_pool(pool_2);
        // check that observed lockup cycle is not updated
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);

        // join validator set with pool_2
        stake::join_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();
        assert!(stake::get_validator_state(pool_2) != constants::inactive_validator_status(), 0);

        // can instantly stake to re-joined validator
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2); 
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist, std=@std)]
    public entry fun test_two_users_stake_in_adjacent_epochs_receive_same_rewards(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
        std: &signer
    ) { 
        std::features::change_feature_flags_for_testing(std, vector<u64>[60], vector<u64>[]);
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup users with APT
        let initial_apt_amount = 10000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, initial_apt_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, initial_apt_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        // *** FIRST EPOCH *** // - Alice deposits - 10,000 Apt
        let alice_deposit = 10000 * constants::one_apt();
        staker::stake(alice, alice_deposit);
        delegation_pool::end_aptos_epoch(); 

        // *** SECOND EPOCH *** // - Bob deposits - 10,000 with staker
        let bob_deposit = 10000 * constants::one_apt();
        staker::stake(bob, bob_deposit);

        let alice_max_withdraw = staker::max_withdraw(signer::address_of(alice));
        let bob_max_withdraw = staker::max_withdraw(signer::address_of(bob));

        // Alice and Bob have the same max withdraw amount
        assert!(alice_max_withdraw == bob_max_withdraw, 1); // 10,045 APT
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, charlie=@0x282828, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist, std=@std)]
    public entry fun test_three_users_stake_in_adjacent_epochs_only_initial_two_receive_same_rewards(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
        std: &signer
    ) { 
        std::features::change_feature_flags_for_testing(std, vector<u64>[60], vector<u64>[]);
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup users with APT
        let initial_apt_amount = 10000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, initial_apt_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, initial_apt_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, initial_apt_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);

        // *** FIRST EPOCH *** // - Alice deposits - 10,000 Apt
        let alice_deposit = 10000 * constants::one_apt();
        staker::stake(alice, alice_deposit);
        delegation_pool::end_aptos_epoch(); 

        // *** SECOND EPOCH *** // - Bob deposits - 10,000 with staker
        let bob_deposit = 10000 * constants::one_apt();
        staker::stake(bob, bob_deposit);
        delegation_pool::end_aptos_epoch(); 
         
         // *** THIRD EPOCH *** // - Charlie deposits - 10,000 with staker
        let charlie_deposit = 10000 * constants::one_apt();
        staker::stake(charlie, charlie_deposit);

        let alice_max_withdraw = staker::max_withdraw(signer::address_of(alice));
        let bob_max_withdraw = staker::max_withdraw(signer::address_of(bob));
        let charlie_max_withdraw = staker::max_withdraw(signer::address_of(charlie));

        // Alice and Bob have the same max withdraw amount
        assert!(alice_max_withdraw == bob_max_withdraw, 1); // 10,045 APT
        assert!(charlie_max_withdraw == charlie_deposit, 1); // 10,000 APT
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist, std=@std)]
    public entry fun test_two_users_stake_in_adjacent_epochs_second_user_gets_rewards_sooner(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
        std: &signer
    ) { 
        std::features::change_feature_flags_for_testing(std, vector<u64>[60], vector<u64>[]);
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup users with APT
        let initial_apt_amount = 10000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, initial_apt_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, initial_apt_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        // *** FIRST EPOCH *** // - Alice deposits - 10,000 Apt
        let alice_deposit = 10000 * constants::one_apt();
        staker::stake(alice, alice_deposit); // can instantly withdraw 10,000 APT

        delegation_pool::end_aptos_epoch(); 

        // *** SECOND EPOCH *** // - Bob deposits - 10,000 with staker
        //1 epoch later, alice still has the initial deposit amount
        let alice_max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(alice_max_withdraw == alice_deposit, 0); // 10,000 APT
        
        let bob_deposit = 10000 * constants::one_apt();
        staker::stake(bob, bob_deposit); // can instantly withdraw 10,000 APT

        delegation_pool::end_aptos_epoch();

        // *** THIRD EPOCH *** //
        let bob_max_withdraw = staker::max_withdraw(signer::address_of(bob));
        // 1 epoch later, bob has already accrued rewards
        assert!(bob_max_withdraw > bob_deposit, 1); // 10,045 APT
    }

    //  _____________________________ Event Emission Tests _____________________________

    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DepositedEvent_emitted(
        julia: &signer,
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
        let deposit_amount = 1000000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        let pre_balance = truAPT::balance_of(signer::address_of(julia));

        // action that emits event
        stake(julia, deposit_amount);

        let post_balance = truAPT::balance_of(signer::address_of(julia));

        // assert number of emitted events
        let deposit_events = event::emitted_events<staker::DepositedEvent>();
        assert!(vector::length(&deposit_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_DepositedEvent(signer::address_of(julia), deposit_amount, post_balance - pre_balance);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
}