#[test_only]
module publisher::withdraw_list_test{
    use std::signer;
    use std::vector;

    use aptos_framework::delegation_pool;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::event;

    // smart contracts
    use publisher::staker::{Self, stake};

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::time;
    use whitelist::master_whitelist;

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_list_single_unlock(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) == 0, 0);
        staker::unlock(alice, deposit_amount);
        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();  

        // user withdraws
        let unlock_nonces =vector<u64>[nonce]; 
        staker::withdraw_list(alice, unlock_nonces);

        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) >= max_withdraw, 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_list_multiple_unlocks(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) == 0, 0);
        staker::unlock(alice, max_withdraw/2);
        let nonce_1 = staker::latest_unlock_nonce();

        staker::unlock(alice, max_withdraw/2);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();  

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces);

        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) >= max_withdraw, 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327692, location=staker)]
    public entry fun test_user_withdraws_list_when_one_unlock_has_not_matured_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount/2);
        let nonce_1 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/2);
        let nonce_2 = staker::latest_unlock_nonce();

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces); // EWITHDRAWAL_NOT_READY
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65547, location=staker)]
    public entry fun test_user_withdraws_list_when_one_unlock_has_already_been_claimed_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount/2);
        let nonce_1 = staker::latest_unlock_nonce();

        staker::unlock(alice, deposit_amount/2);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // claim one unlock already
        staker::withdraw(alice, nonce_1);

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces); // EINVALID_NONCE
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327689, location=staker)]
    public entry fun test_user_withdraws_list_when_not_whitelisted_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount/2);
        let nonce_1 = staker::latest_unlock_nonce();

        staker::unlock(alice, deposit_amount/2);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // whitelisting status changes
        master_whitelist::clear_whitelist_status(whitelist, alice_addr);

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces); // EUSER_NOT_WHITELISTED
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_user_withdraws_list_when_contract_is_paused_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount/2);
        let nonce_1 = staker::latest_unlock_nonce();

        staker::unlock(alice, deposit_amount/2);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // pause staker
        staker::pause(admin);

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, bob=@0x3241, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327690, location=staker)]
    public entry fun test_user_withdraws_list_when_one_unlock_has_a_different_user_fails(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr, signer::address_of(bob)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // users submit unlock requests
        staker::unlock(alice, deposit_amount/2);
        let nonce_1 = staker::latest_unlock_nonce();

        staker::unlock(bob, deposit_amount/2);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces); // ESENDER_MUST_BE_RECEIVER
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_list_with_just_one_withdrawal(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // users submit unlock requests
        staker::unlock(alice, deposit_amount/3);
        let nonce_1 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1]; 
        staker::withdraw_list(alice, unlock_nonces);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_list_three_withdrawals_consecutively_emits_withdrawal_claimed_events(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // users submit unlock requests
        staker::unlock(alice, deposit_amount/3);
        let nonce_1 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);
        let nonce_3 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_1, nonce_2, nonce_3]; 
        staker::withdraw_list(alice, unlock_nonces);

        // assert number of emitted events
        let withdraw_events = event::emitted_events<staker::WithdrawalClaimedEvent>();
        assert!(vector::length(&withdraw_events) == 3, 0);

        // assert event contents
        let expected_event_1 = staker::test_WithdrawalClaimedEvent(alice_addr, deposit_amount/3, nonce_1);
        assert!(event::was_event_emitted(&expected_event_1), 0);
        let expected_event_2 = staker::test_WithdrawalClaimedEvent(alice_addr, deposit_amount/3, nonce_2);
        assert!(event::was_event_emitted(&expected_event_2), 0);
        let expected_event_3 = staker::test_WithdrawalClaimedEvent(alice_addr, deposit_amount/3, nonce_3);
        assert!(event::was_event_emitted(&expected_event_3), 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_user_withdraws_list_three_withdrawals_inconsecutively_emits_withdrawal_claimed_events(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // users submit unlock requests
        staker::unlock(alice, deposit_amount/3);
        let nonce_1 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);
        let nonce_2 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);
        let nonce_3 = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        let unlock_nonces =vector<u64>[nonce_3, nonce_1, nonce_2]; 
        staker::withdraw_list(alice, unlock_nonces);

        // assert number of emitted events
        let withdraw_events = event::emitted_events<staker::WithdrawalClaimedEvent>();
        assert!(vector::length(&withdraw_events) == 3, 0);

        // assert event contents
        let expected_event_1 = staker::test_WithdrawalClaimedEvent(alice_addr, deposit_amount/3, nonce_1);
        assert!(event::was_event_emitted(&expected_event_1), 0);
        let expected_event_2 = staker::test_WithdrawalClaimedEvent(alice_addr, deposit_amount/3, nonce_2);
        assert!(event::was_event_emitted(&expected_event_2), 0);
        let expected_event_3 = staker::test_WithdrawalClaimedEvent(alice_addr, deposit_amount/3, nonce_3);
        assert!(event::was_event_emitted(&expected_event_3), 0);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65569, location=staker)]
    public entry fun test_user_withdraws_list_with_no_nonces_fails(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ){
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let alice_addr = signer::address_of(alice);
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // users submit unlock requests
        staker::unlock(alice, deposit_amount/3);

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);

        // time passes
        time::move_olc_and_epoch_forward();

        staker::unlock(alice, deposit_amount/3);

        // time passes
        time::move_olc_and_epoch_forward();

        // user withdraws
        let unlock_nonces =vector<u64>[]; 
        staker::withdraw_list(alice, unlock_nonces); // ENO_NONCES_PROVIDED
    }
}