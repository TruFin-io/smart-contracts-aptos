#[test_only]
module publisher::allocate_test{
    use std::signer;
    use std::vector;
    
    use aptos_framework::delegation_pool; 
    use aptos_framework::event;

    // smart contracts
    use publisher::staker::{Self, allocate, stake, share_price_scaling_factor};

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker;
    
    //  _____________________________ User Function Tests _____________________________

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_allocate(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        
        //stake
        stake(alice, deposit_amount);

        // allocate
        let allocate_amount = 10 * constants::one_apt(); 
        allocate(alice, bob_addr, allocate_amount);

        let (apt_amount, _, _) = staker::test_allocation(alice_addr, bob_addr);
        assert!(apt_amount == allocate_amount, 0);
    }


    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_allocate_twice_to_same_person(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        //stake
        stake(alice, deposit_amount);

        // allocate
        let allocate_amount = 10 * constants::one_apt(); 
        allocate(alice, signer::address_of(bob), allocate_amount);
        allocate(alice, signer::address_of(bob), allocate_amount);

        let (apt_amount, _, _) = staker::test_allocation(signer::address_of(alice), signer::address_of(bob));
        assert!(apt_amount == (allocate_amount*2), 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_allocate_twice_to_same_person_updates_allocation_share_price(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        //stake
        stake(alice, deposit_amount);

        // allocate
        let allocate_amount = 10 * constants::one_apt(); 
        allocate(alice, signer::address_of(bob), allocate_amount);
        let (old_allocation_amount, old_allocation_num, old_allocation_denom) = staker::test_allocation(signer::address_of(alice), signer::address_of(bob));
        let old_allocation_share_price = (old_allocation_num/old_allocation_denom);

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        let (price_num, price_denom) = staker::share_price();
        let share_price = (price_num/price_denom);

        allocate(alice, signer::address_of(bob), allocate_amount);

        let (new_allocation_amount, new_num, new_denom) = staker::test_allocation(signer::address_of(alice), signer::address_of(bob));

        let scaling_factor: u256 = share_price_scaling_factor();
        let old_allocation_amount_u256: u256 = (old_allocation_amount as u256);
        let expected_new_num = old_allocation_amount_u256 * scaling_factor + (allocate_amount as u256) * scaling_factor;

        let expected_new_denom_summand1 = (old_allocation_amount_u256 * scaling_factor / old_allocation_share_price);
        let expected_new_denom_summand2 = ((allocate_amount as u256) * scaling_factor / share_price);
        let expected_new_denom = expected_new_denom_summand1 + expected_new_denom_summand2;

        assert!(new_allocation_amount == (allocate_amount*2), 0);
        assert!(new_num == expected_new_num, 0);
        assert!(new_denom == expected_new_denom, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65557, location=staker)]
    public entry fun test_allocate_less_than_one_apt_fails(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // transfer and stake APT
        stake(alice, deposit_amount);

        let allocate_amount = 1_000; 
        allocate(alice, signer::address_of(bob), allocate_amount); // EALLOCATION_UNDER_ONE_APT
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65559, location=staker)]
    public entry fun test_allocate_to_zero_address_fails(
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
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // transfer and stake APT
        stake(alice, deposit_amount);

        let allocate_amount = 1_000; 
        allocate(alice, @0x0, allocate_amount); // EINVALID_RECIPIENT
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65559, location=staker)]
    public entry fun test_allocate_to_oneself_fails(
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
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // transfer and stake APT
        stake(alice, deposit_amount);

        let allocate_amount = 1_000; 
        allocate(alice, signer::address_of(alice), allocate_amount); // EINVALID_RECIPIENT
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65544, location=staker)]
    public entry fun test_allocate_more_than_max_withdraw_fails(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // transfer and stake APT
        stake(alice, deposit_amount);

        let allocate_amount = 10_000 * constants::one_apt(); 
        allocate(alice, signer::address_of(bob), allocate_amount); // EINSUFFICIENT_BALANCE
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_allocating_when_paused_fails(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // transfer and stake APT
        stake(alice, deposit_amount);

        // pause staker
        staker::pause(admin);        

        allocate(alice, signer::address_of(bob), deposit_amount); // ECONTRACT_PAUSED
    }

    //  _____________________________ Event Emission Tests _____________________________

    #[test(alice=@0xE0A1B, bob=@0xABC123B, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_AllocatedEvent_emitted(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        //stake
        stake(alice, deposit_amount);

        // allocate
        let allocate_amount = 10 * constants::one_apt(); 
        allocate(alice, signer::address_of(bob), allocate_amount); 

        // assert number of emitted events
        let allocate_events = event::emitted_events<staker::AllocatedEvent>();
        assert!(vector::length(&allocate_events) == 1, 0);

        // assert event contents
        let share_price_num: u256 = 100000000000000000000000000;
        let share_price_denom: u256 = 1000000000000000000;
        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        let expected_event = staker::test_AllocatedEvent(signer::address_of(alice), signer::address_of(bob), allocate_amount, allocate_amount, share_price_num, share_price_denom,
        total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&expected_event), 0);
    }

    #[test(alice=@0xE0A1B, bob=@0xABC123B, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_AllocatedEvents_data(
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
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1_000_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        //stake
        stake(alice, deposit_amount);

        // allocate
        let allocate_amount = 10 * constants::one_apt(); 
        allocate(alice, signer::address_of(bob), allocate_amount);
        let (first_total_allocated_amount, first_total_allocated_share_price_num, first_total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));


        // assert number of emitted events
        let allocate_events = event::emitted_events<staker::AllocatedEvent>();
        assert!(vector::length(&allocate_events) == 1, 0);

        // allocate again
        let new_allocate_amount = 20 * constants::one_apt(); 
        allocate(alice, signer::address_of(bob), new_allocate_amount); 

        // assert number of emitted events
        allocate_events = event::emitted_events<staker::AllocatedEvent>();
        assert!(vector::length(&allocate_events) == 2, 0);

        // assert event contents
        let share_price_num: u256 =   100000000000000000000000000;
        let share_price_denom: u256 = 1000000000000000000;

        let first_expected_event = staker::test_AllocatedEvent(signer::address_of(alice), signer::address_of(bob), allocate_amount, allocate_amount, 
                                                               share_price_num, share_price_denom, first_total_allocated_amount, first_total_allocated_share_price_num, 
                                                               first_total_allocated_share_price_denom);
                                                               
        assert!(event::was_event_emitted(&first_expected_event), 0);

        // manually calculate the share price after the second allocation
        let factor: u256 = share_price_scaling_factor();
        let total_allocation_amount = allocate_amount + new_allocate_amount;
        let new_allocation_share_price_num = factor * (total_allocation_amount as u256);
        let new_allocation_share_price_denom = ((allocate_amount as u256) * factor * share_price_denom / share_price_num) +  
                            ((new_allocate_amount as u256) * factor * share_price_denom / share_price_num);
        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        
        let second_expected_event = staker::test_AllocatedEvent(signer::address_of(alice), signer::address_of(bob), new_allocate_amount, 
                                                                allocate_amount + new_allocate_amount, new_allocation_share_price_num, 
                                                                new_allocation_share_price_denom, total_allocated_amount, total_allocated_share_price_num,
                                                                total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&second_expected_event), 0);
    }
}