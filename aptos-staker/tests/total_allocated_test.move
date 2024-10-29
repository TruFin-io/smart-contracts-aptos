#[test_only]
module publisher::total_allocated_test{
    use std::signer;

    use aptos_framework::delegation_pool; 

    // smart contracts
    use publisher::staker::{Self, total_allocated, share_price, share_price_scaling_factor};

    // test modules
    use publisher::account_setup;
    use publisher::setup_test_staker;
    use publisher::constants;

  #[test(alice=@0xE0A1, bob=@0xABC123, chloe=@0xDEF123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_total_allocated_for_user_with_one_allocation(
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
        staker::stake(alice, deposit_amount);

        // allocate APT to other users
        let allocate_amount: u64 = 1* constants::one_apt(); 
        staker::allocate(alice, signer::address_of(bob), allocate_amount);
        
        // share price at allocation
        let (num, denom) = share_price();
        let sp = num/denom;

        let (total_allocated_amount, total_allocated_num, total_allocated_denom) = total_allocated(signer::address_of(alice));
        let total_allocated_price = total_allocated_num/total_allocated_denom;

        assert!(total_allocated_price == sp, 0);
        assert!(total_allocated_amount == allocate_amount, 0);
    }


    #[test(alice=@0xE0A1, bob=@0xABC123, chloe=@0xDEF123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_total_allocated_for_user_with_no_allocations(
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
        staker::stake(alice, deposit_amount);

        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = total_allocated(signer::address_of(alice));

        assert!(total_allocated_amount == 0, 0);
        assert!(total_allocated_share_price_num == 0, 0);
        assert!(total_allocated_share_price_denom == 0, 0);
    }

  #[test(alice=@0xE0A1, bob=@0xABC123, chloe=@0xDEF123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_total_allocated_for_user_with_many_allocations(
        alice: &signer,
        bob: &signer,
        chloe: &signer,
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
        staker::stake(alice, deposit_amount);

        // allocate APT to other users
        let allocate_amount: u64 = 1* constants::one_apt(); 
        staker::allocate(alice, signer::address_of(bob), allocate_amount);
        staker::allocate(alice, signer::address_of(chloe), allocate_amount);
        
        // share price at allocation
        let (num, denom) = share_price();
        let share_price = num/denom;

        let (total_allocated_amount, total_allocation_num, total_allocation_denom) = total_allocated(signer::address_of(alice));
        let total_allocation_price = total_allocation_num/total_allocation_denom;

        assert!(total_allocation_price == share_price, 0);
        assert!(total_allocated_amount == allocate_amount * 2, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, chloe=@0xDEF123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_total_allocated_for_user_with_many_allocations_at_different_times(
        alice: &signer,
        bob: &signer,
        chloe: &signer,
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
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(chloe)]);

        // transfer and stake APT
        staker::stake(alice, deposit_amount);

        // allocate APT
        let allocate_amount: u64 = 1* constants::one_apt(); 

        staker::allocate(alice, signer::address_of(chloe), allocate_amount);

        let (old_total_allocation_amount, old_total_allocation_num, old_total_allocation_denom) = total_allocated(signer::address_of(alice));
        let old_total_allocation_price = old_total_allocation_num/old_total_allocation_denom;

        // accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        staker::allocate(alice, signer::address_of(chloe), allocate_amount);

        // calculate what the updated total allocated share price should be
        let scaling_factor: u256 = share_price_scaling_factor();
        let old_allocation_amount_u256 = (old_total_allocation_amount as u256);
        let expected_new_num = (old_allocation_amount_u256) * scaling_factor + (allocate_amount as u256) * scaling_factor;

        let (num, denom) = share_price();
        let share_price = num/denom;

        let expected_new_denom_summand1 = (old_allocation_amount_u256 * scaling_factor / old_total_allocation_price);
        let expected_new_denom_summand2 = ((allocate_amount as u256) * scaling_factor / share_price);
        let expected_new_denom = expected_new_denom_summand1 + expected_new_denom_summand2;

        let expected_new_price = expected_new_num / expected_new_denom;

        // get total allocated 
        let (new_total_allocation_amount, new_total_allocation_num, new_total_allocation_denom) = total_allocated(signer::address_of(alice));
        let new_total_allocation_price = new_total_allocation_num/new_total_allocation_denom;    

        assert!(new_total_allocation_amount == old_total_allocation_amount + allocate_amount, 0);
        assert!(new_total_allocation_price == expected_new_price, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, chloe=@0xDEF123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_total_allocated_for_many_users_with_many_allocations_at_different_times(
        alice: &signer,
        bob: &signer,
        chloe: &signer,
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
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(chloe)]);

        // transfer and stake APT
        staker::stake(alice, deposit_amount);
        staker::stake(bob, deposit_amount);

        // allocate APT
        let allocate_amount: u64 = 1* constants::one_apt(); 
        staker::allocate(alice, signer::address_of(bob), allocate_amount);
        staker::allocate(alice, signer::address_of(chloe), allocate_amount);

        // share price at allocation
        let (num, denom) = share_price();
        let price_one = num/denom;

        // accrue rewards
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        staker::allocate(bob, signer::address_of(alice), allocate_amount);
        staker::allocate(bob, signer::address_of(chloe), allocate_amount);

        // share price at allocation
        let (num, denom) = share_price();
        let price_two = num/denom;

        // get total allocated
        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = total_allocated(signer::address_of(alice));
        let total_allocation_price_alice = total_allocated_share_price_num/total_allocated_share_price_denom;

        assert!(total_allocation_price_alice == price_one, 0);
        assert!(total_allocated_amount == allocate_amount * 2, 0);

        // get total allocated
        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = total_allocated(signer::address_of(bob));
        let total_allocation_price_bob = total_allocated_share_price_num/total_allocated_share_price_denom;


        assert!(total_allocation_price_bob == price_two, 0);
        assert!(total_allocated_amount == allocate_amount * 2, 0);
    }
}