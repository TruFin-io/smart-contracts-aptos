#[test_only]
module publisher::share_price_test {
    use std::signer;

    use aptos_framework::delegation_pool; 
    use aptos_framework::stake;
    use aptos_framework::staking_config;

    // smart contracts
    use publisher::staker::{Self, stake, total_shares, total_staked, share_price, share_price_scaling_factor};
    use publisher::truAPT;
    
    // test modules
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::setup_test_delegation_pool;
    use publisher::constants;
    use publisher::time;

    #[test(admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher, src = @src_account, validator=@0xDEA3)]
    public entry fun test_share_price_when_no_shares_exist(
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // get the share price before any stake
        let (price_num, price_denom) = share_price();

        let staked = total_staked();
        assert!(staked == 0, 0);

        // verify the share price is 1 and price numerator is scaled
        assert!(price_num == 1 * share_price_scaling_factor(), 0);
        assert!(price_denom == 1, 0);
    }

    #[test(julia=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_share_price_one_stake_one_epoch(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // first stake
        assert!(total_shares() == 0, 0);
        stake(julia, 123 * constants::one_apt());

        let (price_num, price_denom) = share_price();
        let price = price_num / price_denom;

        // share price should remain 1
        assert!(price == 1 * share_price_scaling_factor(), 0);

        // end epoch, add_stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        assert!(total_shares() > 0, 0);

        // verify share price is 1
        (price_num, price_denom) = share_price();
        price = price_num / price_denom;

        assert!(price == 1 * share_price_scaling_factor(), 0);
    }

    #[test(alice=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_share_price_does_not_change_when_fees_are_collected_no_fees(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // first stake
        assert!(total_shares() == 0, 0);
        stake(alice, 123 * constants::one_apt());

        let (price_num, price_denom) = share_price();
        let price = price_num / price_denom;

        // share price should remain 1
        assert!(price == 1 * share_price_scaling_factor(), 0);

        // end epoch, add_stake fees are reimbursed.
        delegation_pool::end_aptos_epoch();

        staker::collect_fees();

        // verify share price is still 1
        (price_num, price_denom) = share_price();
        price = price_num / price_denom;

        assert!(price == 1 * share_price_scaling_factor(), 0);
    }
   
    #[test(alice=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_share_price_does_not_change_when_fees_are_collected(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // first stake
        stake(alice, 123 * constants::one_apt());

        let (price_num, price_denom) = share_price();
        let price = price_num / price_denom;

        // share price should remain 1
        assert!(price == 1 * share_price_scaling_factor(), 0);

        // end epoch, add_stake fees are reimbursed. Rewards accrue.
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        (price_num, price_denom) = share_price();
        let pre_price = price_num / price_denom;

        staker::collect_fees();

        // verify share price did not change after fees were collected
        (price_num, price_denom) = share_price();
        let post_price = price_num / price_denom;

        assert!(pre_price == post_price, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_share_price_remains_constant_when_pool_is_inactive(
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
        let other_pool = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // initialize with zero commission for simplicity
        );
        staker::add_pool(admin, other_pool);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some APT with other pool
        staker::stake_to_specific_pool(alice, stake_amount, other_pool);

        // leave validator set
        stake::leave_validator_set(validator_2, other_pool);
        delegation_pool::end_aptos_epoch();

        // rewards should not accrue
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let (price_num, price_denom) = share_price();
        
        // verify the share price is still 1
        assert!(price_num/price_denom == share_price_scaling_factor(), 0);
    }

    #[test(julia=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher, 
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_share_price_one_stake_two_epochs(
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

        // first stake
        stake(julia, 123 * constants::one_apt());

        // end 1st epoch, add_stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        // get share price after the 1st epoch ended
        let (price_num, price_denom) = share_price();
        let price_after_1st_epoch = price_num / price_denom;

        // end 2nd epoch, staking rewards are paid to the pool
        delegation_pool::end_aptos_epoch();

        // verify share price increased
        (price_num, price_denom) = share_price();
        let price_after_2nd_epoch = price_num / price_denom;
        assert!(price_after_2nd_epoch > price_after_1st_epoch, 0);
    }

    #[test(julia=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher, 
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_share_price_increases_multiple_stakes_and_epochs(
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

        // first stake
        stake(julia, 123 * constants::one_apt());

        // end 1st epoch, add_stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        // verify share price is 1 after the first epoch ended
        let (price_num, price_denom) = share_price();
        let price_after_1st_epoch = price_num / price_denom;
        assert!(price_after_1st_epoch == 1 * share_price_scaling_factor(), 0);

        // end 2nd epoch, staking rewards are paid to the pool
        delegation_pool::end_aptos_epoch();

        // verify share price increased
        (price_num, price_denom) = share_price();
        let price_after_2nd_epoch = price_num / price_denom;
        assert!(price_after_2nd_epoch > price_after_1st_epoch, 0);

        // second stake
        stake(julia, 123 * constants::one_apt());

        // end 3rd epoch, add_stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        // verify share price increased
        (price_num, price_denom) = share_price();
        let price_after_3rd_epoch = price_num / price_denom;
        assert!(price_after_3rd_epoch > price_after_2nd_epoch, 0);

        // end 2nd epoch, staking rewards are paid to the pool
        delegation_pool::end_aptos_epoch();

        // verify share price increased
        (price_num, price_denom) = share_price();
        let price_after_4th_epoch = price_num / price_denom;
        assert!(price_after_4th_epoch > price_after_3rd_epoch, 0);
    }

    #[test(alice=@0x1234, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_share_price_not_changed_by_partial_unlock(
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

        // stake some tokens.
        stake(alice, 100 * constants::one_apt());

        // end epoch to allow the add_stake fees to be reimbursed and move stake to active state.
        delegation_pool::end_aptos_epoch();

        let (price_num, price_denom) = share_price();
        let share_price_pre_unlock = price_num/price_denom;

        // unlock half the shares
        staker::unlock(alice, 50 * constants::one_apt());

        // share price should not have changed after unlock as no rewards have been accrued
        (price_num, price_denom) = share_price();
        let share_price_post_unlock = price_num/price_denom;
        assert!(share_price_post_unlock == share_price_pre_unlock, 0);

        delegation_pool::end_aptos_epoch();

        // share price should have increased after the epoch.
        (price_num, price_denom) = share_price();
        let share_price_post_epoch = price_num/price_denom;
        assert!(share_price_post_epoch > share_price_post_unlock, 0);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_total_shares(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        // mint some truAPT tokens
        let mint_amount = 123 * 10^8;
        truAPT::mint(resource_account, signer::address_of(admin), mint_amount);

        // verify total shares
        assert!(total_shares() == mint_amount, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_higher_rewards_rate_results_in_higher_share_price_over_same_time_period(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        stake(alice, stake_amount);
        delegation_pool::end_aptos_epoch();
        let (num, denom) = share_price();  
        let initial_share_price = num/denom;

        // accrue rewards at 1% rate
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // calculate % increase
        (num, denom) = share_price();
        let share_price_after_1st_accrual = (num/denom);
        let increase_amount = share_price_after_1st_accrual - initial_share_price;
        let percentage_increase_1st_accrual = (increase_amount * 100) / initial_share_price;

        // change rewards rate to 10%
        staking_config::update_rewards_rate(aptos_framework, 10, 100);
        
        // accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // calculate % increase
        (num, denom) = share_price();
        let increase_amount_2nd_accrual = (num/denom) - share_price_after_1st_accrual;
        let percentage_increase_2nd_accrual = (increase_amount_2nd_accrual * 100) / share_price_after_1st_accrual;

        assert!(percentage_increase_2nd_accrual > percentage_increase_1st_accrual, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_share_price_remains_one_after_staking_to_zero_rewards_rate_pool(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
        // make 0% rewards rate pool
        staking_config::update_rewards_rate(aptos_framework, 0, 100);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some APT with zero rewards rate pool
        staker::stake(alice, stake_amount);

        // time passes
        time::move_olc_and_epoch_forward();

        // rewards should not accrue
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let (num, denom) = share_price();
        let share_price = num/denom;

        // assert
        assert!((share_price as u64) == constants::one_apt(), 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_share_price_remains_constant_as_pool_becomes_inactive(
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
        delegation_pool::end_aptos_epoch();

        // leave validator set with pool_2
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        // share price at point of inactivation
        let (num, denom) = staker::share_price();
        let share_price_active = num/denom;

        let observed_lockup_cycle = delegation_pool::observed_lockup_cycle(pool_2);

        // ensure pool is inactive
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 0);

        // expire lockup afterwards
        time::move_olc_and_epoch_forward();

        delegation_pool::synchronize_delegation_pool(pool_2);
        assert!(delegation_pool::observed_lockup_cycle(pool_2) == observed_lockup_cycle, 0);

        // share price during inactivation
        let (num, denom) = staker::share_price();
        let share_price_inactive = num/denom;

        assert!(share_price_inactive == share_price_active, 0);
    }
}