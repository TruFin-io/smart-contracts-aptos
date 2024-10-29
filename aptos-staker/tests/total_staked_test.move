#[test_only]
module publisher::total_staked_test{
    use std::signer;

    use aptos_framework::delegation_pool; 
    use aptos_framework::staking_config;
    use aptos_framework::stake;

    // smart contracts
    use publisher::staker::{Self, test_set_pool, total_staked, stake, stake_to_specific_pool, add_pool};

    // test modules
    use publisher::account_setup;
    use publisher::setup_test_staker;
    use publisher::setup_test_delegation_pool;
    use publisher::constants;
    use publisher::time;


    #[test(julia=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_total_staked(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, stake_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);
    
        // stake some tokens
        stake(julia, stake_amount);

        // verify the total staked amount has increased by the user stake
        assert!(total_staked() == stake_amount, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_total_staked_with_multiple_delegation_pools(
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

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // stake some tokens with delegation pool one
        stake(alice, stake_amount);

        // add a second pool, which will end the current aptos epoch (moving previous stake into active)
        // delegation_pool_2 will become the default delegation_pool
        let delegation_pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        test_set_pool(delegation_pool_2);

        assert!(total_staked() == stake_amount, 0);

        // stake some tokens with delegation_pool_2
        stake(alice, stake_amount);

        // end epoch to allow the add_stake fees to be reimbursed
        delegation_pool::end_aptos_epoch();

        // the total staked amount should now be the sum of the two stakes plus the rewards of the first stake
        assert!(total_staked() >= stake_amount *2, 0);
    }
    
    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_total_staked_one_epoch(
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
        let delegation_pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // stake some tokens with delegation pool one
        stake(alice, stake_amount);
        
        // add delegation_pool_2 as the default delegation_pool without ending the epoch
        test_set_pool(delegation_pool_2);

        assert!(total_staked() == stake_amount, 0);

        // stake some tokens with delegation_pool_2
        stake(alice, stake_amount);

        // the total staked amount should now be the sum of the two stakes
        assert!(total_staked() == stake_amount *2, 0);
    }


    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_rewards_accrue_according_to_validator_rewards_rate(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_1: &signer,
        whitelist: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        // basic pool default rewards rate is 1%
        let default_rewards_rate_num = 1;
        let default_rewards_rate_denom = 100;

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // stake some tokens with delegation pool
        stake(alice, stake_amount);
        delegation_pool::end_aptos_epoch();

        // balance before accrual
        let pre_accrual = total_staked();

        // accrue rewards
        time::move_olc_and_epoch_forward();  

        let post_accrual = total_staked();

        let predicted_increase = (pre_accrual * default_rewards_rate_num) / default_rewards_rate_denom;
        let predicted_post_accrual = pre_accrual + predicted_increase;

        // assert the new amount matches the amount predicted by the rewards rate
        assert!(post_accrual == predicted_post_accrual, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_rewards_accrues_equally_across_multiple_validators_with_same_rewards_rate(
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
        let other_pool = setup_test_delegation_pool::create_basic_pool(validator_2);
        add_pool(admin, other_pool);

        // basic pool default rewards rate is 1%
        let default_rewards_rate_num = 1;
        let default_rewards_rate_denom = 100;

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // stake some APT with default delegation pool
        stake(alice, stake_amount);
        delegation_pool::end_aptos_epoch();

        // stake some APT with other pool
        stake_to_specific_pool(alice, stake_amount, other_pool);
        delegation_pool::end_aptos_epoch();
        let pre_accrual_both = total_staked();

        // rewards accrue
        time::move_olc_and_epoch_forward();  
        let post_accrual_both = total_staked();
        
        // assert % increase
        let predicted_increase_both_pools = (pre_accrual_both * default_rewards_rate_num) / default_rewards_rate_denom;
        let predicted_accrual_both = pre_accrual_both + predicted_increase_both_pools;
        assert!(post_accrual_both == predicted_accrual_both, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_total_staked_is_sum_of_active_stakes_across_validators(
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
        let other_pool = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // initialize with zero commission for simplicity
        );
        add_pool(admin, other_pool);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // stake some APT with default delegation pool
        stake(alice, stake_amount);
        delegation_pool::end_aptos_epoch();

        // stake some APT with other pool
        stake_to_specific_pool(alice, stake_amount, other_pool);
        delegation_pool::end_aptos_epoch();

        // rewards accrue
        time::move_olc_and_epoch_forward();

        let (active_default, _, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let (active_other, _, _) = delegation_pool::get_stake(other_pool, signer::address_of(resource_account));
        let total_active = active_default + active_other;
        assert!(total_active == total_staked(), 0);
    }
    
    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_total_staked_is_correct_with_active_and_inactive_pools(
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
        let other_pool = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // initialize with zero commission for simplicity
        );
        add_pool(admin, other_pool);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 4);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // stake some APT with default delegation pool
        stake(alice, stake_amount);
        delegation_pool::end_aptos_epoch();

        // stake some APT with other pool
        stake_to_specific_pool(alice, stake_amount, other_pool);
        delegation_pool::end_aptos_epoch();

        // leave validator set
        stake::leave_validator_set(validator_2, other_pool);
        delegation_pool::end_aptos_epoch();

        // rewards accrue on default pool but not the other pool that left
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let (active_default, _, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let (active_other, _, _) = delegation_pool::get_stake(other_pool, signer::address_of(resource_account));
        let total_active = active_default + active_other;
        assert!(total_active == total_staked(), 0);
        assert!(active_default > active_other, 0);
    }
    
    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_total_staked_remains_constant_when_pool_is_inactive(
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
        add_pool(admin, other_pool);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some APT with other pool
        staker::stake_to_specific_pool(alice, stake_amount, other_pool);

        // leave validator set
        stake::leave_validator_set(validator_2, other_pool);
        delegation_pool::end_aptos_epoch();

        // get active stake of inactive pool
        let (active, _, _) = delegation_pool::get_stake(other_pool, signer::address_of(resource_account));

        // rewards should not accrue
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // assert that active stake has not increased
        assert!(active == total_staked(), 0);
        assert!(active == stake_amount, 0);
    }

    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_rewards_remain_zero_after_staking_to_zero_rewards_rate_pool(
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
        // setup zero rewards rate pool
        let other_pool = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // initialize with zero commission for simplicity
        );
        add_pool(admin, other_pool);

        let stake_amount = 123 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, stake_amount * 2);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // stake some APT with zero rewards rate pool
        stake_to_specific_pool(alice, stake_amount, other_pool);

        // time passes
        time::move_olc_and_epoch_forward();

        // assert
        assert!(stake_amount == total_staked(), 0);
    }


    #[test(alice=@0xE0A1,admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_1=@0xDEA3, validator_2=@0xFEB4, whitelist=@whitelist)]
    public entry fun test_higher_rewards_rate_results_in_higher_rewards_over_same_time_period(
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
        let initial_staked = total_staked();

        // accrue rewards at 1% rate
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // calculate % increase
        let stake_after_1st_accrual = total_staked();
        let increase_amount = stake_after_1st_accrual - initial_staked;
        let percentage_increase_1st_accrual = (increase_amount * 100) / initial_staked;

        // change rewards rate to 10%
        staking_config::update_rewards_rate(aptos_framework, 10, 100);
        
        // accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // calculate % increase
        let increase_amount_2nd_accrual = total_staked() - stake_after_1st_accrual;
        let percentage_increase_2nd_accrual = (increase_amount_2nd_accrual * 100) / stake_after_1st_accrual;

        assert!(percentage_increase_2nd_accrual > percentage_increase_1st_accrual, 0);
    }
}