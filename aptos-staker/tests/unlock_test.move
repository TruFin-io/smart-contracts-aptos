#[test_only]
module publisher::unlock_test {
    use std::signer;
    use std::vector;

    use aptos_framework::delegation_pool;
    use aptos_framework::event;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::coin;

    // smart contracts
    use publisher::staker::{Self, stake};
    use publisher::truAPT;

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::setup_test_delegation_pool;
    use publisher::time;

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_partial_amount(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        let pool_address = staker::default_pool();

        // stake some tokens.
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state.
        delegation_pool::end_aptos_epoch();

        // unlock half the shares
        staker::unlock(alice, 50 * constants::one_apt());
        assert!(truAPT::balance_of(signer::address_of(alice)) == 50 * constants::one_apt(), 0);

        // check unlock nonce
        let nonce = staker::latest_unlock_nonce();
        assert!(nonce == 1, 0);
        
        // unlocked amount should have been moved to pending_inactive stake
        let(active, _, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 50 * constants::one_apt(), 0);
        // can lose at most one coin during the unlock
        assert!((50 * constants::one_apt() - pending_inactive) <= 1, 0);

        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 50 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool_address), 0); // olc == 0, as "time hasn't passed yet"
        assert!(delegation_pool == pool_address, 0); // time hasn't passed yet
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_within_same_olc_increases_pending_inactive_stake(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        let pool_address = staker::default_pool();
        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        
        // pool is empty
        assert!(active == 0, 0);
        assert!(pending_inactive == 0, 0);
        assert!(inactive == 0, 0);
   
        // stake 300 APT
        let staked_amount = 300 * constants::one_apt();
        stake(alice, staked_amount);
        
        // end epoch to allow the add_stake fees to be reimbursed
        delegation_pool::end_aptos_epoch();

        // staked amount is active stake
        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == staked_amount, 0);
        assert!(pending_inactive == 0, 0);
        assert!(inactive == 0, 0);

        // first unlock for 100 APT
        let unlocked_amount = 100 * constants::one_apt();
        staker::unlock(alice, unlocked_amount);

        // unlocked amount moves to pending_inactive stake. 
        // can lose 1 Octa during the unlock due to rounding errors.
        let(active, _, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 200 * constants::one_apt(), 0);
        assert!(pending_inactive == unlocked_amount - 1, 0);
        assert!(inactive == 0, 0);

        // some time passes within the same olc
        timestamp::fast_forward_seconds(constants::new_olc_period() / 3);
        delegation_pool::end_aptos_epoch();
  
        // second unlock for 100 APT within the same olc adds unstaked amount to pending_inactive
        staker::unlock(alice, unlocked_amount);
        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));

        assert!(active == 100 * constants::one_apt() + 2 * constants::one_apt() + 1, 0); // includes 2 APT reward and 1 Octa error
        assert!(pending_inactive == 2 * unlocked_amount + 1 * constants::one_apt() - 3, 0);  // includes 1 APT reward and 3 Octa error
        assert!(inactive == 0, 0);
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_in_future_olc_transfers_inactive_stake_to_staker(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // delegation pool is empty
        let pool_address = staker::default_pool();
        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 0, 0);
        assert!(pending_inactive == 0, 0);
        assert!(inactive == 0, 0);

        // staker has 1 APT balance
        let staker_balance = coin::balance<AptosCoin>(signer::address_of(resource_account));
        assert!(staker_balance == constants::one_apt(), 0);

         // Alice stakes 300 APT
        let staked_amount = 300 * constants::one_apt();
        let add_stake_fees = delegation_pool::get_add_stake_fee(pool_address, staked_amount);
        stake(alice, staked_amount);
        
        // staked amount is added to active stake net of add_stake fees
        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == staked_amount - add_stake_fees, 0);
        assert!(pending_inactive == 0, 0);
        assert!(inactive == 0, 0);

        // epoch ends, add stake fees are reimbursed
        delegation_pool::end_aptos_epoch();
        
        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == staked_amount, 0);
        assert!(pending_inactive == 0, 0);
        assert!(inactive == 0, 0);

        // first unlock for 100 APT, unlocked amount moves to pending_inactive stake.
        let first_unlocked_amount = 100 * constants::one_apt();
        staker::unlock(alice, first_unlocked_amount);

        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 200 * constants::one_apt(), 0);
        assert!(pending_inactive == first_unlocked_amount - 1, 0);
        assert!(inactive == 0, 0);

        // olc ends, pending_inactive stake is moved to inactive stake
        time::move_olc_and_epoch_forward();  

        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 200 * constants::one_apt() + 2 * constants::one_apt(), 0); // includes 1 APT reward a
        assert!(pending_inactive == 0, 0);
        assert!(inactive == first_unlocked_amount + 1 * constants::one_apt() - 2, 0); // includes 1 APT reward and 2 Octa error
  
        // second unlock for 50 APT, unstaked amount moves to pending_inactive, inactive stake is pushed pushed to the staker
        let second_unlocked_amount = 50 * constants::one_apt();
        staker::unlock(alice, second_unlocked_amount);

        let(active, inactive, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 150 * constants::one_apt() + 2 * constants::one_apt() + 1, 0); // includes 2 APT reward and 1 Octa error
        assert!(pending_inactive == second_unlocked_amount - 1, 0); // includes 1 Octa error
        assert!(inactive == 0, 0);

        let staker_balance = coin::balance<AptosCoin>(signer::address_of(resource_account));
        assert!(staker_balance == first_unlocked_amount + 2 * constants::one_apt() - 2, 0);
    }

    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDEFF, whitelist=@whitelist)]
    public entry fun test_unlock_partial_amount_from_specific_pool(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add second delegation pool
        staker::add_pool(admin, pool_2);

        // stake some tokens to added pool
        staker::stake_to_specific_pool(alice, 100 * constants::one_apt(), pool_2);

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state.
        delegation_pool::end_aptos_epoch();

        // unlock half the shares
        staker::unlock_from_specific_pool(alice, 50 * constants::one_apt(), pool_2);
        assert!(truAPT::balance_of(signer::address_of(alice)) == 50 * constants::one_apt(), 0);

        // check unlock nonce
        let nonce = staker::latest_unlock_nonce();
        assert!(nonce == 1, 0);
        
        // unlocked amount should have been moved to pending_inactive stake
        let(active, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active == 50 * constants::one_apt(), 0);
        // can lose at most one coin during the unlock
        assert!((50 * constants::one_apt() - pending_inactive) <= 1, 0);

        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 50 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool_2), 0); 
        assert!(delegation_pool == pool_2, 0);
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_full_amount(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        let pool_address = staker::default_pool();

        // stake some tokens.
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state.
        delegation_pool::end_aptos_epoch();

        // unlock all of the shares
        staker::unlock(alice, 100 * constants::one_apt());
        assert!(truAPT::balance_of(signer::address_of(alice)) == 0, 0);

        // check unlock nonce
        let nonce = staker::latest_unlock_nonce();
        assert!(nonce == 1, 0);
       
        // unlocked amount should have been moved to pending_inactive stake
        let(active, _, pending_inactive) = delegation_pool::get_stake(pool_address, signer::address_of(resource_account));
        assert!(active == 11 * constants::one_apt(), 0);
        // can lose at most one coin during the unlock
        assert!((100 * constants::one_apt() - pending_inactive) <= 1, 0);

        // assert unlock has been entered into the hashmap
        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 100 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool_address), 0); // time hasn't passed yet
        assert!(delegation_pool == pool_address, 0); // time hasn't passed yet
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEA3, whitelist=@whitelist)]
    public entry fun test_unlock_from_pool_with_commission_percentage(
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
        let deposit_amount = 10_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2 * deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
    
        // stake APT with 0 commission pool
        staker::stake(alice, deposit_amount);
        // stake APT with commission pool
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);

        // two epochs pass to accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // unlock from both pools
        staker::unlock(alice, deposit_amount);  // unlock from 0 commission pool
        staker::unlock_from_specific_pool(alice, deposit_amount, pool_2); // unlock from commission pool
        let(_, _, pending_inactive_no_commission) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let(_, _, pending_inactive_commission) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));

        // pending inactive should be equal as no rewards have accrued on unlocked amount yet
        assert!(pending_inactive_no_commission == pending_inactive_commission, 0);
        
        // end epoch for more rewards to accrue
        delegation_pool::end_aptos_epoch();
        (_, _, pending_inactive_no_commission) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        (_, _, pending_inactive_commission) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));

        // check that commission has been taken from the rewards 
        assert!(pending_inactive_no_commission - pending_inactive_commission > constants::one_apt(), 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_unlock_from_pool_with_inactive_state(
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

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);
        
        // unlock from inactive pool
        staker::unlock_from_specific_pool(alice, deposit_amount, pool_2);

        // ensure everything is moved to pending_inactive
        let (_, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(deposit_amount - pending_inactive <= 1 , 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_unlock_partial_amount_from_pool_with_inactive_state(
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

        // stake APT
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);

        // leave validator set
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);
        
        // unlock from inactive pool
        staker::unlock_from_specific_pool(alice, deposit_amount/2, pool_2);

        // ensure half the stake is moved to pending_inactive
        let (active, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(deposit_amount/2 - pending_inactive <= 1, 0);
        assert!(active == deposit_amount/2, 0);
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDEFF, whitelist=@whitelist)]
    public entry fun test_unlock_full_amount_from_specific_pool(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        staker::add_pool(admin, pool_2);

        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool_2);        

        // stake some tokens.
        staker::stake_to_specific_pool(alice, 100 * constants::one_apt(), pool_2);

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state.
        delegation_pool::end_aptos_epoch();

        // unlock all of the shares
        staker::unlock_from_specific_pool(alice, 100 * constants::one_apt(), pool_2);
        assert!(truAPT::balance_of(signer::address_of(alice)) == 0, 0);

        // check unlock nonce
        let nonce = staker::latest_unlock_nonce();
        assert!(nonce == 1, 0);
       
        // unlocked amount should have been moved to pending_inactive stake
        let(active, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active == 11  * constants::one_apt(), 0);

        // can lose at most one coin during the unlock
        assert!((100 * constants::one_apt() - pending_inactive) <= 1, 0);

        // assert unlock has been entered into the hashmap
        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 100 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool_2), 0);
        assert!(delegation_pool == pool_2, 0);
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDEFF, whitelist=@whitelist)]
    public entry fun test_can_unlock_from_disabled_delegation_pool(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        staker::add_pool(admin, pool_2);

        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool_2);
 

        // stake some tokens.
        staker::stake_to_specific_pool(alice, 100 * constants::one_apt(), pool_2);

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state.
        delegation_pool::end_aptos_epoch();

        // disable the delegation pool
        staker::disable_pool(admin, pool_2);

        // unlock all of the shares
        staker::unlock_from_specific_pool(alice, 100 * constants::one_apt(), pool_2);

        // check unlock nonce
        let nonce = staker::latest_unlock_nonce();
        assert!(nonce == 1, 0);

        // assert unlock has been entered into the hashmap
        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 100 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool_2), 0);
        assert!(delegation_pool == pool_2, 0);
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, bob=@0x2345, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65556, location=staker)]
    public entry fun test_unlock_when_other_unlock_drains_active_stake_fails(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        // This test is to illustrate a potential issue we need to be aware of: 
        // UserA stakes and their stake becomes active. If UserB stakes they can unlock up to UserA's staked amount.
        // If UserA then wants to unlock, they have to wait until UserB's stake becomes active.
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);     
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 200 * constants::one_apt());
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, 200 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        // stake some tokens with alice
        stake(alice, 200 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();

        // stake some tokens with bob
        stake(bob, 200 * constants::one_apt());

        // bob unlocks immediately
        staker::unlock(bob, truAPT::balance_of(signer::address_of(bob)));

        // now if alice wants to unlock, it will fail with EUNLOCK_AMOUNT_TOO_HIGH
        staker::unlock(alice, 200 * constants::one_apt());
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, bob=@0x2345, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65542, location=delegation_pool)]
    public entry fun test_unlock_when_not_enough_active_stake_fails(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 400 * constants::one_apt());
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, 200 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // stake some tokens with bob
        stake(bob, 20 * constants::one_apt());

        // stake some tokens with alice
        stake(alice, 200 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();

        // stake more tokens with alice
        stake(alice, 200 * constants::one_apt());

        // alice first unlock works
        staker::unlock(alice, 200 * constants::one_apt());

        // this second unlock will fail with delegation_pool::ENOT_ENOUGH_ACTIVE_STAKE_TO_UNLOCK
        // because the add_stake fees for the second deposit haven't been reimboursed yet
        staker::unlock(alice, 200 * constants::one_apt());
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65543, location=staker)]
    public entry fun test_unlock_zero_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some tokens
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock 0
        staker::unlock(alice, 0);
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_sweeps_anything_below_min_unstake(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 20 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // stake some tokens
        stake(alice, 20 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock so that less than 10 APT would remain staked
        staker::unlock(alice, 11 * constants::one_apt());
        let nonce = staker::latest_unlock_nonce();

        // all of users APT should have been burned 
        assert!(truAPT::balance_of(signer::address_of(alice)) == 0, 0);
        
        // assert full amount has been unlocked
        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 20 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool), 0);
        assert!(delegation_pool == pool, 0);

        // assert full amount has been moved to pending_inactive stake
        let(_, _, pending_inactive) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        assert!(pending_inactive + 1 >= 20 * constants::one_apt(), 0);
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_does_not_sweep_anything_above_min_unlock(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 20 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some tokens
        stake(alice, 20 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock so that exactly 10 APT would remain staked
        staker::unlock(alice, 10 * constants::one_apt());
        let nonce = staker::latest_unlock_nonce();

        // Only half the users TruAPT should have been burned
        assert!(truAPT::balance_of(signer::address_of(alice)) == 10 * constants::one_apt(), 0);
        
        // assert 10 APT have been unlocked 
        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 10 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool), 0);
        assert!(delegation_pool == pool, 0);

        // assert 10 APT have been moved to pending_inactive stake
        let(_, _, pending_inactive) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        assert!(pending_inactive == 10 * constants::one_apt(), 0);
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, bob=@12523, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, validator_2=@3412, whitelist=@whitelist)]
    #[expected_failure(abort_code=65556, location=staker)]
    public entry fun test_withdraw_with_multiple_pools_and_sweeps_can_lead_to_fund_lockout(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        validator_2: &signer,
        whitelist: &signer,
    ) {
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        staker::add_pool(admin, pool_2);

        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 30 * constants::one_apt());
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, 10 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);
        
        // deposit initial amount of 11 APT on both pools
        initial_deposit(aptos_framework, whitelist, pool);
        aptos_coin::mint(aptos_framework, signer::address_of(whitelist), 11 * constants::one_apt());
        staker::stake_to_specific_pool(whitelist, 11 * constants::one_apt(), pool_2);

        // stake some tokens
        stake(alice, 20 * constants::one_apt());
        staker::stake_to_specific_pool(alice, 10 * constants::one_apt(), pool_2);
        staker::stake_to_specific_pool(bob, 10 * constants::one_apt(), pool_2);

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock so that less than 10 APT would remain staked
        staker::unlock(alice, 15 * constants::one_apt());
        staker::unlock_from_specific_pool(alice, 10 * constants::one_apt(), pool_2);
        let nonce = staker::latest_unlock_nonce();

        // all of users APT should have been burned 
        assert!(truAPT::balance_of(signer::address_of(alice)) == 0, 0);
        
        // assert full amount has been unlocked
        let(amount, user, olc, delegation_pool) = staker::test_unlock_request(nonce);
        assert!(amount == 15 * constants::one_apt(), 0);
        assert!(user == signer::address_of(alice), 0);
        assert!(olc == delegation_pool::observed_lockup_cycle(pool), 0);
        assert!(delegation_pool == pool_2, 0);

        // fails with EUNLOCK_AMOUNT_TOO_HIGH
        staker::unlock_from_specific_pool(bob, 10 * constants::one_apt(), pool);
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65543, location=staker)]
    public entry fun test_unlock_less_than_min_unlock_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some tokens
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock less than min unlock amount
        staker::unlock(alice, 9 * constants::one_apt());
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65543, location=staker)]
    public entry fun test_unlock_less_than_min_unlock_despite_other_unlocks_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some tokens
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock
        staker::unlock(alice, 10 * constants::one_apt());

        // unlock less than min unlock amount
        staker::unlock(alice, 9 * constants::one_apt());
    }
    
    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65550, location=staker)]
    public entry fun test_unlock_from_non_existent_pool_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some tokens
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock from non-existent pool
        staker::unlock_from_specific_pool(alice, 100 * constants::one_apt(), @0x123);
    }
    
    #[test(alice=@0x1234,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure (abort_code=65544, location=staker)]
    public entry fun test_unlock_more_than_deposited_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some tokens
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock more than deposited
        staker::unlock(alice, 150 * constants::one_apt());
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDEFF, whitelist=@whitelist)]
    #[expected_failure(abort_code=65556, location=staker)]
    public entry fun test_unlock_more_than_deposited_from_specific_pool_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add new delegation pool
        staker::add_pool(admin, pool_2);

        // stake some tokens to default pool
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state
        delegation_pool::end_aptos_epoch();
       
        // unlock from added pool even though nothing has been staked to it yet fails with EUNLOCK_AMOUNT_TOO_HIGH
        staker::unlock_from_specific_pool(alice, 100 * constants::one_apt(), pool_2);
    }

    #[test(julia=@0xE0A1, tiff=@0xABC01, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_users_stake_and_unlock_after_one_epoch(
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
        let small_amount = 10_000 * constants::one_apt();
        let large_amount = 1_000_000 * constants::one_apt(); 
        
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, small_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, tiff, large_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia), signer::address_of(tiff)]);
       
        // user stakes
        stake(tiff, large_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(tiff, small_amount);
        delegation_pool::end_aptos_epoch();

        // user stakes
        stake(julia, small_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(julia, small_amount);
    }

    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65556, location=staker)]
    public entry fun test_unlock_when_active_stake_drops_below_pool_min_coins_fails(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        // whitelist and setup user with APT
        let deposit_amount = 20 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // stake some tokens with the default pool
        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        let pool_address = staker::default_pool();
        let resource_account_address = signer::address_of(resource_account);

        let (active, _, _) = delegation_pool::get_stake(pool_address, resource_account_address);

        // unlock request for an amount that brings the active stake below the min pool coins
        let min_pool_coins = 10 * constants::one_apt();
        let unlock_amount = 11 * constants::one_apt();
        assert!(active - unlock_amount < min_pool_coins, 0);

        // fails with EUNLOCK_AMOUNT_TOO_HIGH
        staker::unlock(julia, unlock_amount); 
    }

    #[test(alice=@0xE0A1, bob=@0x1288, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_unlock_rewards_amount_after_unlocking_deposit_amount(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        // whitelist and setup user with APT
        let deposit_amount = 10 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // stake some tokens with the default pool
        stake(alice, deposit_amount);

        let i = 0;
        while (i < 1000){
            delegation_pool::end_aptos_epoch();
            i = i + 1;
        };

        // remove initial stake amount
        staker::unlock(alice, deposit_amount);

        let unlock_amount =  staker::max_withdraw(signer::address_of(alice));

        // remove rewards accrued (must be greater than the minimum unlock amount)
        staker::unlock(alice, unlock_amount);
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDEFF, whitelist=@whitelist)]
    #[expected_failure(abort_code=65556, location=staker)]
    public entry fun test_unlock_amount_greater_than_active_stake_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer,
    ) { 
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        // add second delegation pool
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        staker::add_pool(admin, pool_2);

        // setup whitelisted user with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2 * deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // stake APT tokens to both pools
        staker::stake_to_specific_pool(alice, deposit_amount, staker::default_pool());
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);

        // add stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        // rewards accrue
        delegation_pool::end_aptos_epoch();

        // unlock request for an amount greater than the active stake should fail
        let unlock_amount = 1_100 * constants::one_apt();
        
        // fails with EUNLOCK_AMOUNT_TOO_HIGH
        staker::unlock_from_specific_pool(alice, unlock_amount, staker::default_pool());
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_unlock_when_paused_fails(
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

        // pause staker
        staker::pause(admin);

        staker::unlock(alice, deposit_amount); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_unlock_from_specific_pool_when_paused_fails(
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

        staker::stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // pause staker
        staker::pause(admin);

        staker::unlock_from_specific_pool(alice, deposit_amount, pool); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_unlock_from_active_and_inactive_pool_burns_same_number_of_shares(
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
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2*deposit_amount);

        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // add treasury deposit to pool_2 to assure the MIN_COINS_ON_SHARES_POOL
        initial_deposit(aptos_framework, whitelist, pool_2);

        // user stakes
        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        staker::stake(alice, deposit_amount);
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

        let truapt_balance = truAPT::balance_of(signer::address_of(alice));
        // unlock from inactive pool
        staker::unlock_from_specific_pool(alice, deposit_amount/2, pool_2);
        let nonce = staker::latest_unlock_nonce();
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);
        assert!(staker::is_claimable(nonce) == true, 0);

        let post_unlock_balance_1 = truAPT::balance_of(signer::address_of(alice));
        let truapt_burned_inactive = truapt_balance - post_unlock_balance_1;

        // unlock from active pool
        staker::unlock(alice, deposit_amount/2);
        let post_unlock_balance_2 = truAPT::balance_of(signer::address_of(alice));
        let truapt_burned_active = post_unlock_balance_1 - post_unlock_balance_2;

        assert!(truapt_burned_inactive == truapt_burned_active, 0);
    }

//  _____________________________ Event Emission Tests _____________________________
    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_UnlockedEvent_emitted(
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

        // whitelist and setup for unlock
        let deposit_amount = 1000000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);
        initial_deposit(aptos_framework, whitelist, pool);

        stake(julia, deposit_amount);
        delegation_pool::end_aptos_epoch();

        let pre_balance = truAPT::balance_of(signer::address_of(julia));

        // action that emits event
        staker::unlock(julia, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        let post_balance = truAPT::balance_of(signer::address_of(julia));

        // assert number of emitted events
        let unlock_events = event::emitted_events<staker::UnlockedEvent>();
        assert!(vector::length(&unlock_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_UnlockedEvent(signer::address_of(julia), deposit_amount, nonce, pre_balance - post_balance);
        assert!(event::was_event_emitted(&expected_event), 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_all_user_funds_can_be_unlocked_one_olc_after_validator_has_gone_inactive(
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

        // user stakes to active pool_2
        staker::stake_to_specific_pool(alice, deposit_amount/2, pool_2);

        // ACCRUE
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // validator (pool_2) leaves validator set 
        stake::leave_validator_set(validator_2, pool_2);
        
        let (active_at_leave, _, _ ) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));

        // time passes + olc ends
        time::move_olc_and_epoch_forward();

        // pool is now inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // delegation pool stake still shows as active (despite the inactive validator)
        let (active, inactive, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(inactive == 0, 0);
        assert!(pending_inactive == 0, 0);
        assert!(active >= active_at_leave, 0); // greater because still accrued rewards when validator was pending-inactive
        
        // user comes notices validator has gone inactive and would like to withdraw all their funds
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));

        // now user wants to unlock entire amount from inactive pool
        staker::unlock_from_specific_pool(alice, max_withdraw, pool_2);
        let nonce = staker::latest_unlock_nonce();

        // check max withdraw amount has been unlocked
        let (_, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(pending_inactive == max_withdraw-1, 0);

        staker::withdraw(alice, nonce);
        // check MIN_COINS_ON_SHARES_POOL remain
        let (active, _, _) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active >= constants::min_coins_on_shares_pool(), 0);
    }


    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_all_user_funds_can_be_unlocked_one_epoch_after_validator_has_gone_inactive(
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

        // ACCRUE
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);

        let (active_at_leave, _, _ ) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));

        // end epoch
        delegation_pool::end_aptos_epoch();

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        let (active, inactive, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        
        assert!(inactive == 0, 0);
        assert!(pending_inactive == 0, 0);
        assert!(active >= active_at_leave, 0); // greater because still accrued rewards when validator was pending-inactive
        
        // user would like to withdraw all their funds
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));

        staker::unlock_from_specific_pool(alice, max_withdraw, pool_2);
        let nonce = staker::latest_unlock_nonce();
        // check max withdraw amount has been unlocked
        let (_, _, pending_inactive) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(pending_inactive == max_withdraw-1, 0);

        // time passes
        time::move_olc_and_epoch_forward();

        staker::withdraw(alice, nonce);

        // check MIN_COINS_ON_SHARES_POOL remain
        let (active, _, _) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active >= constants::min_coins_on_shares_pool(), 0);
    }
}