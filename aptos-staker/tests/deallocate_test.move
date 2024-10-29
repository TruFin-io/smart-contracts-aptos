#[test_only]
module publisher::deallocate_test {
    use std::signer;
    use std::vector;

    use aptos_framework::event;

    // smart contracts
    use publisher::staker::{Self, stake, allocate, deallocate, allocations, test_allocation};

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker;

    //  _____________________________ User Function Tests _____________________________

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_deallocate_reduces_allocation (
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to Bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);
        
        // get the allocation info
        let (allocation_amount, allocation_price_num , allocation_price_denom) = test_allocation(signer::address_of(alice), signer::address_of(bob));
        assert!(allocation_amount == allocate_amount, 0);

        // reduce allocation
        let deallocate_amount = 20 * constants::one_apt();
        deallocate(alice, signer::address_of(bob), deallocate_amount,);

        // verify that the allocation amount was reduced and the allocation share price has not changed
        let (reduced_allocation_amount, reduced_allocation_price_num, reduced_allocation_price_denom) = test_allocation(signer::address_of(alice), signer::address_of(bob));
        assert!(reduced_allocation_amount == (allocation_amount - deallocate_amount), 0);
        assert!(reduced_allocation_price_num / reduced_allocation_price_denom == allocation_price_num / allocation_price_denom, 0);
    }


    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_deallocate_full_amount_removes_the_allocation (
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to Bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);

        // verify that the allocation exists
        let alice_allocations = allocations(signer::address_of(alice));
        assert!(vector::length(&alice_allocations) == 1, 0);

        // deallocate the full amount
        deallocate(alice, signer::address_of(bob), allocate_amount);

        // verify that the allocation was removed
        let alice_allocations = allocations(signer::address_of(alice));
        assert!(vector::length(&alice_allocations) == 0, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327689, location=staker)]
    public entry fun test_deallocate_non_whitelisted_address_fails(
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

        // setup user with APT but not whitelist
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1_000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[]);

        // fails with EUSER_NOT_WHITELISTED
        deallocate(alice, signer::address_of(bob), 10 * constants::one_apt());
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_deallocate_zero_recipient_address_fails(
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
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
     
        // fails with EZERO_ADDRESS
        deallocate(alice, @0x0, 10 * constants::one_apt());
    }


    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65558, location=staker)]
    public entry fun test_deallocate_no_existing_allocations_fails(
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
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 10 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        // fails with ENO_ALLOCATIONS
        deallocate(alice, signer::address_of(bob), 20 * constants::one_apt());
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, charlie=@0xC8A87E, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65561, location=staker)]
    public entry fun test_deallocate_no_recipient_allocation_fails(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to Bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);

        // deallocate from Charlie fails with ENO_ALLOCATION_TO_RECIPIENT
        deallocate(alice, signer::address_of(charlie), 20 * constants::one_apt());
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65562, location=staker)]
    public entry fun test_deallocate_excessive_amount_fails(
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to Bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);

        // deallocate more than was allocated fails with EEXCESS_DEALLOCATION
        deallocate(alice, signer::address_of(bob), allocate_amount + 1);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65557, location=staker)]
    public entry fun test_deallocate_under_1_apt_fails(
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);

        // fails with EALLOCATION_UNDER_ONE_APT
        deallocate(alice, signer::address_of(bob), 99 * constants::one_apt() + 1);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_deallocating_when_paused_fails(
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

        allocate(alice, signer::address_of(bob), deposit_amount);

        // pause staker
        staker::pause(admin);

        deallocate(alice, signer::address_of(bob), deposit_amount); // ECONTRACT_PAUSED
    }

    //  _____________________________ Event Emission Tests _____________________________

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DeallocatedEvent_emitted(
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);

        // reduce allocation
        let deallocate_amount = 20 * constants::one_apt();
        deallocate(alice, signer::address_of(bob), deallocate_amount);

        // assert number of emitted events
        let deallocated_events = event::emitted_events<staker::DeallocatedEvent>();
        assert!(vector::length(&deallocated_events) == 1, 0);

        // assert event contents
        let (share_price_num, share_price_denom) = staker::share_price();
        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        let expected_event = staker::test_DeallocatedEvent(signer::address_of(alice), signer::address_of(bob), deallocate_amount, 
                                                           allocate_amount - deallocate_amount, share_price_num, share_price_denom,
                                                           total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&expected_event), 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DeallocatedEvents_data(
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
        
        // stake
        stake(alice, deposit_amount);

        // allocate 100 APT to bob
        let allocate_amount = 100 * constants::one_apt();
        allocate(alice, signer::address_of(bob), allocate_amount);

        // reduce allocation
        let deallocate_amount = 20 * constants::one_apt();
        deallocate(alice, signer::address_of(bob), deallocate_amount);
        let (first_total_allocated_amount, first_total_allocated_share_price_num, first_total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        // assert number of emitted events
        let deallocated_events = event::emitted_events<staker::DeallocatedEvent>();
        assert!(vector::length(&deallocated_events) == 1, 0);

        // reduce allocation again 
        let new_deallocate_amount = 40 * constants::one_apt();
        deallocate(alice, signer::address_of(bob), new_deallocate_amount);

        // assert number of emitted events
        deallocated_events = event::emitted_events<staker::DeallocatedEvent>();
        assert!(vector::length(&deallocated_events) == 2, 0);

        // assert event contents
        let (share_price_num, share_price_denom) = staker::share_price();
        
        let first_expected_event = staker::test_DeallocatedEvent(signer::address_of(alice), signer::address_of(bob), deallocate_amount, 
            allocate_amount - deallocate_amount, share_price_num, share_price_denom, first_total_allocated_amount, first_total_allocated_share_price_num, first_total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&first_expected_event), 0);

        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        let second_expected_event = staker::test_DeallocatedEvent(signer::address_of(alice), signer::address_of(bob), new_deallocate_amount, 
            allocate_amount - deallocate_amount - new_deallocate_amount, share_price_num, share_price_denom, total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&second_expected_event), 0);
    }
}