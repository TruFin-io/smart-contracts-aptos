#[test_only]
module publisher::fees_test{
    use std::signer;
    use std::vector;

    use aptos_framework::delegation_pool;
    use aptos_framework::event;

    // smart contracts
    use publisher::staker::{Self, stake, collect_fees, total_shares};
    use publisher::truAPT;

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};

    #[test(alice=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_does_not_mint_fees_when_no_rewards_accrue(
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

        assert!(total_shares() == 0, 0);

        // first stake
        stake(alice, 123 * constants::one_apt());

        let pre_supply = total_shares();
        collect_fees();
        let post_supply = total_shares();

        // ensure treasury was not minted fees
        assert!(pre_supply == post_supply, 0);
    }
    
    #[test(alice=@0xE0A1,admin = @default_admin, aptos_framework=@0x1, resource_account = @publisher,
    src = @src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_when_total_staked_is_equal_to_tax_exempt_amount(
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

        assert!(total_shares() == 0, 0);

        stake(alice, 123 * constants::one_apt());

        // accrue rewards (minimum 2 epochs required to accrue enough rewards to mint treasury shares upon fee collection)
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let total_shares = total_shares();

        // collect fees (taxabale_amount is > 0, rewards are taxed)
        collect_fees();
        let total_shares_after_fees_collection = total_shares();
        assert!(total_shares_after_fees_collection > total_shares, 0);

        // total staked should equal to the tax exempt amount
        let total_staked = staker::total_staked();
        let tax_exempt_amount = staker::tax_exempt_stake();
        assert!(total_staked == tax_exempt_amount, 0);

        // collect fees again (taxable_amount is 0)
        collect_fees();

        // assert that no new shares were minted (ie no new fees were collected)
        let total_shares_after_second_fees_collection = total_shares();
        assert!(total_shares_after_fees_collection == total_shares_after_second_fees_collection, 0);
    }

    #[test(alice=@0xE0A1, bob=@0x1288, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_when_total_staked_is_less_than_tax_exempt_amount(
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

        // accrue a lot of rewards such that total_staked exceeds tax exempt stake
        let i = 0;
        while (i < 100){
            delegation_pool::end_aptos_epoch();
            i = i + 1;
        };

        let total_staked = staker::total_staked();
        let tax_exempt_amount = staker::tax_exempt_stake();
        // total staked should be greater than tax exempt amount
        assert!(total_staked > tax_exempt_amount, 0);
        
        // remove initial stake amount
        staker::unlock(alice, deposit_amount);

        let total_staked = staker::total_staked();
        let tax_exempt_amount = staker::tax_exempt_stake();
        // total staked should be less than tax exempt amount
        assert!(total_staked < tax_exempt_amount, 0);

        let total_shares = total_shares();

        collect_fees();

        // assert that no fees were charged
        let total_shares_after_fees_collection = total_shares();
        assert!(total_shares_after_fees_collection == total_shares, 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_mints_fees_when_rewards_accrue(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // first stake
        stake(alice, 123 * constants::one_apt());

        // end epoch, add_stake fees are reimbursed. Rewards accrue.
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let pre_balance = truAPT::balance_of(signer::address_of(treasury));
        collect_fees();
        let post_balance = truAPT::balance_of(signer::address_of(treasury));

        // ensure treasury was minted fees
        assert!(pre_balance < post_balance, 0);
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_mints_correct_fees_for_multiple_stakes(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let deposit_amount = 100 * constants::one_apt();
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // first stake
        stake(alice, deposit_amount);

        // Add_stake fees are reimbursed, rewards accrue.
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // stake again
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let pre_balance = truAPT::balance_of(signer::address_of(treasury));

        let total_staked = staker::total_staked();
        let (price_num, price_denom) = staker::share_price();
        
        // to get how many rewards accrued, we check how much is currently staked, and how much has entered/left the protocol
        let taxable_amount = total_staked - deposit_amount - deposit_amount;
        let expected_fees = (taxable_amount * constants::default_fee() as u256) * staker::share_price_scaling_factor() * price_denom / (price_num * (constants::fee_precision() as u256));

        // unlock. Collects fees.
        staker::unlock(alice, 50 * constants::one_apt());

        let post_balance = truAPT::balance_of(signer::address_of(treasury));

        assert!((post_balance-pre_balance as u256) == expected_fees, 0);

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let total_staked_2 = staker::total_staked();
        (price_num, price_denom) = staker::share_price();
        
        taxable_amount = total_staked_2 + 50 * constants::one_apt() - total_staked;
        expected_fees = (taxable_amount * constants::default_fee() as u256) * staker::share_price_scaling_factor() * price_denom / (price_num * (constants::fee_precision() as u256));
        pre_balance = truAPT::balance_of(signer::address_of(treasury));

        collect_fees();

        post_balance = truAPT::balance_of(signer::address_of(treasury));

        assert!((post_balance-pre_balance as u256) == expected_fees, 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_mints_correct_fees_for_multiple_collections(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let deposit_amount = 100 * constants::one_apt();
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // first stake
        stake(alice, deposit_amount);

        // Add_stake fees are reimbursed, rewards accrue.
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let total_staked = staker::total_staked();
        let (price_num, price_denom) = staker::share_price();
        let taxable_amount = total_staked - deposit_amount;
        let expected_fees = (taxable_amount * constants::default_fee() as u256) * staker::share_price_scaling_factor() * price_denom / (price_num * (constants::fee_precision() as u256));
        
        let pre_balance = truAPT::balance_of(signer::address_of(treasury));

        collect_fees();

        let post_balance = truAPT::balance_of(signer::address_of(treasury));

        assert!((post_balance-pre_balance as u256) == expected_fees, 0);

        // stake again
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();


        let total_staked_2 = staker::total_staked();
        (price_num, price_denom) = staker::share_price();
        let taxable_amount = total_staked_2 - deposit_amount - total_staked;
        let expected_fees = (taxable_amount * constants::default_fee() as u256) * staker::share_price_scaling_factor() * price_denom / (price_num * (constants::fee_precision() as u256));

        let pre_balance = truAPT::balance_of(signer::address_of(treasury));

        // unlock. Collects fees.
        staker::unlock(alice, 50 * constants::one_apt());

        let post_balance = truAPT::balance_of(signer::address_of(treasury));

        assert!((post_balance-pre_balance as u256) == expected_fees, 0);

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let total_staked_3 = staker::total_staked();
        (price_num, price_denom) = staker::share_price();
        
        // to get how many rewards accrued, we check how much is currently staked, and how much has entered/left the protocol
        taxable_amount = total_staked_3 + 50 * constants::one_apt() - total_staked_2;
        expected_fees = (taxable_amount * constants::default_fee() as u256) * staker::share_price_scaling_factor() * price_denom / (price_num * (constants::fee_precision() as u256));
        pre_balance = truAPT::balance_of(signer::address_of(treasury));

        collect_fees();

        post_balance = truAPT::balance_of(signer::address_of(treasury));

        assert!((post_balance-pre_balance as u256) == expected_fees, 0);
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_does_not_mint_fees_on_unlocked_rewards(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // first stake
        stake(alice, 123 * constants::one_apt());

        // end epoch, add_stake fees are reimbursed.
        delegation_pool::end_aptos_epoch();

        staker::unlock(alice, 123 * constants::one_apt());
        
        // rewards accrue
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        let pre_balance = truAPT::balance_of(signer::address_of(treasury));

        collect_fees();

        let post_balance = truAPT::balance_of(signer::address_of(treasury));

        // treasury is expected to receive 1% rewards each epoch, of which 10% is minted as fees
        // only stake remaining is the initial deposit of 11 APT so calculating fees based off of this amount
        let expected_rewards = 3 * (11 * constants::one_apt()) / 1000;

        // ensure treasury was not minted fees for the unlocked amount
        assert!(pre_balance + expected_rewards >= post_balance, 0);
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_collect_fees_when_paused_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // stake
        stake(alice, 123 * constants::one_apt());

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // pause staker
        staker::pause(admin);

        collect_fees(); // ECONTRACT_PAUSED
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_collect_fees_emits_FeesCollectedEvent(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // first stake
        stake(alice, 123 * constants::one_apt());

        // end epoch, add_stake fees are reimbursed.
        delegation_pool::end_aptos_epoch();

        staker::unlock(alice, 123 * constants::one_apt());
        
        // rewards accrue
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        let pre_balance = truAPT::balance_of(signer::address_of(treasury));
        let (price_num, price_denom) = staker::share_price();

        collect_fees();

        let post_balance = truAPT::balance_of(signer::address_of(treasury));

        let treasury_increase = post_balance - pre_balance;

        // assert number of emitted events
        let fees_collected_event = event::emitted_events<staker::FeesCollectedEvent>();
        assert!(vector::length(&fees_collected_event) == 1, 0);

        // assert event contents
        let expected_event = staker::test_FeesCollectedEvent(treasury_increase, price_num, price_denom);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
}