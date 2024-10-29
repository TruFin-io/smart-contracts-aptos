#[test_only]
module publisher::distribute_rewards_test{
    use std::signer;
    use std::vector;

    use aptos_framework::event;
    use aptos_framework::delegation_pool;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset;
    use aptos_framework::account;

    // smart contracts
    use publisher::staker::{Self, allocate, stake, distribute_rewards, distribute_all, deallocate};
    use publisher::truAPT;

    // test modules
    use publisher::constants::{Self, one_apt};
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};

    //  _____________________________ Helper functions _____________________________
    public fun set_up_allocation(distributor: &signer, recipient: &signer, aptos_framework: &signer, whitelist: &signer){
        let distributor_address = signer::address_of(distributor);
        let recipient_address = signer::address_of(recipient);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, distributor, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, recipient, 10 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[distributor_address, recipient_address]);
        
        //stake
        stake(distributor, deposit_amount);

        // allocate
        allocate(distributor, recipient_address, 50 * one_apt());
    }

    public fun set_up_allocations(distributor: &signer, first_recipient: &signer, second_recipient: &signer, aptos_framework: &signer, whitelist: &signer){
        let distributor_address = signer::address_of(distributor);
        let first_recipient_address = signer::address_of(first_recipient);
        let second_recipient_address = signer::address_of(second_recipient);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, distributor, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, first_recipient, 10 * constants::one_apt());
        account_setup::setup_account_and_mint_APT(aptos_framework, second_recipient, 10 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[distributor_address, first_recipient_address, second_recipient_address]);
        
        //stake
        stake(distributor, deposit_amount);

        // allocate
        allocate(distributor, first_recipient_address, 50 * one_apt());
        allocate(distributor, second_recipient_address, 50 * one_apt());
    }

    //  _____________________________ Distribution Tests _____________________________
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_rewards_in_truapt_when_no_rewards_accrued(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let bob_addr = signer::address_of(bob);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocation(alice, bob, aptos_framework, whitelist);

        // distribute rewards
        let pre_balance = truAPT::balance_of(bob_addr);
        distribute_rewards(alice, bob_addr, false);
        let post_balance = truAPT::balance_of(bob_addr);
        
        assert!(pre_balance == post_balance, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_rewards_in_apt_when_no_rewards_accrued(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let bob_addr = signer::address_of(bob);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocation(alice, bob, aptos_framework, whitelist);
        let pre_balance = coin::balance<AptosCoin>(bob_addr);

        // distribute rewards
        distribute_rewards(alice, bob_addr, true);

        let post_balance = coin::balance<AptosCoin>(bob_addr);
        assert!(pre_balance == post_balance, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_rewards_in_truapt(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);
        let treasury_addr = signer::address_of(treasury);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        set_up_allocation(alice, bob, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // distribute rewards
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_alice = truAPT::balance_of(alice_addr);
        let pre_balance_treasury = truAPT::balance_of(treasury_addr);

        distribute_rewards(alice, bob_addr, false);

        let post_balance_bob = truAPT::balance_of(bob_addr);
        let post_balance_alice = truAPT::balance_of(alice_addr);
        let post_balance_treasury = truAPT::balance_of(treasury_addr);
        
        let (share_price_num, share_price_denom) = staker::share_price();

        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;
        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;

        // check truAPT balance of recipient and treasury increased, while distributor's decreased
        assert!((post_balance_bob - pre_balance_bob as u256) == distributed_truAPT_after_fees, 0);
        assert!((post_balance_alice as u256) + distributed_truAPT_after_fees + fees == (pre_balance_alice as u256), 0);
        assert!((pre_balance_treasury as u256) + fees == (post_balance_treasury as u256), 0);

        let (allocated_amount, allocated_share_price_num, allocated_share_price_denom) = staker::test_allocation(alice_addr, bob_addr);
        
        // check allocated amount is unchanged
        assert!(allocated_amount == 50 * constants::one_apt(), 0);

        // check allocation share price updated to current share price
        assert!(allocated_share_price_num == share_price_num, 0);
        assert!(allocated_share_price_denom == share_price_denom, 0);
    }
   
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_rewards_in_apt(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);
        let treasury_addr = signer::address_of(treasury);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        set_up_allocation(alice, bob, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // mint APT to distributor
        aptos_coin::mint(aptos_framework, alice_addr, 30 * constants::one_apt());
        
       // distribute rewards
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_alice = truAPT::balance_of(alice_addr);
        let pre_balance_treasury = truAPT::balance_of(treasury_addr);
        let pre_apt_balance_alice = coin::balance<AptosCoin>(alice_addr);
        let pre_apt_balance_bob = coin::balance<AptosCoin>(bob_addr);

        distribute_rewards(alice, bob_addr, true);
        
        let (share_price_num, share_price_denom) = staker::share_price();
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;

        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;
        let distributed_APT_after_fees = (distributed_truAPT_after_fees as u256) * share_price_num / (share_price_denom * staker::share_price_scaling_factor());

        // check APT balance of recipient increased
        assert!((coin::balance<AptosCoin>(bob_addr) - pre_apt_balance_bob  as u256) == distributed_APT_after_fees, 0);

        // check APT balance of distributor decreased
        assert!((coin::balance<AptosCoin>(alice_addr) as u256) + distributed_APT_after_fees == (pre_apt_balance_alice as u256), 0);

        // check truAPT balance of recipient remained the same, while the distributor paid the fees
        assert!(pre_balance_bob == truAPT::balance_of(bob_addr), 0);
        assert!(pre_balance_alice == truAPT::balance_of(alice_addr) + (fees as u64), 0);

        // check treasury received fees
        assert!((pre_balance_treasury as u256) + fees == (truAPT::balance_of(treasury_addr) as u256), 0);

        let (allocated_amount, allocated_share_price_num, allocated_share_price_denom) = staker::test_allocation(alice_addr, bob_addr);
        
        // check allocated amount is unchanged
        assert!(allocated_amount == 50 * constants::one_apt(), 0);

        // check allocation share price updated to current share price
        assert!(allocated_share_price_num == share_price_num, 0);
        assert!(allocated_share_price_denom == share_price_denom, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65542, location=coin)]
    public entry fun test_distribute_rewards_in_apt_fails_when_distributor_has_no_apt(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let bob_addr = signer::address_of(bob);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocation(alice, bob, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // distribute rewards fails with EINSUFFICIENT_BALANCE
        distribute_rewards(alice, bob_addr, true);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65540, location=fungible_asset)]
    public entry fun test_distribute_rewards_in_truapt_fails_when_distributor_has_no_truapt(
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

        set_up_allocation(alice, bob, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let balance = truAPT::balance_of(alice_addr);
        let truAPT_metadata = truAPT::get_metadata();
        primary_fungible_store::transfer(alice, truAPT_metadata, bob_addr, balance);

        // distribute rewards fails with EINSUFFICIENT_BALANCE
        distribute_rewards(alice, bob_addr, false);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65558, location=staker)]
    public entry fun test_distribute_rewards_fails_when_distributor_has_no_allocations(
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
        
        // set up and whitelist distributor's account
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 10 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr, bob_addr]);
        
        // distribute rewards fails with ENO_ALLOCATION
        distribute_rewards(alice, bob_addr, false);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_rewards_creates_recipient_account_if_no_account_exists(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        
        // set up and whitelist distributor's account
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 50 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[alice_addr]);
        
        stake(alice, 50 * one_apt());

        allocate(alice, @0x2828, 50 * one_apt());

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // check recipient does not have an account
        let recipient_account_exists = account::exists_at(@0x2828);
        assert!(!recipient_account_exists, 0);

        distribute_rewards(alice, @0x2828, false);

        // check recipient account was created
        let recipient_account_exists = account::exists_at(@0x2828);
        assert!(recipient_account_exists, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65561, location=staker)]
    public entry fun test_distribute_rewards_fails_when_distributor_has_no_allocations_to_recipient(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let admin_addr = signer::address_of(admin);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        
        set_up_allocation(alice, bob, aptos_framework, whitelist);

        // distribute rewards fails with ENO_ALLOCATION
        distribute_rewards(alice, admin_addr, false);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_distribute_rewards_when_paused_fails(
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
        
        let distributor_address = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[distributor_address]);
        
        //stake
        stake(alice, deposit_amount);

        allocate(alice, bob_addr, deposit_amount/2);

        // pause staker
        staker::pause(admin);

        distribute_rewards(alice, bob_addr, false); // ECONTRACT_PAUSED
    }

    //  _____________________________ DistributeAll Tests ______________________________

    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_all_in_truapt_when_no_rewards_accrued(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let bob_addr = signer::address_of(bob);
        let cleo_addr = signer::address_of(cleo);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);

        // distribute rewards
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_cleo = truAPT::balance_of(cleo_addr);

        distribute_all(alice, false);

        let post_balance_bob = truAPT::balance_of(bob_addr);
        let post_balance_cleo = truAPT::balance_of(cleo_addr);
        
        assert!(pre_balance_bob == post_balance_bob, 0);
        assert!(pre_balance_cleo == post_balance_cleo, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_all_in_apt_when_no_rewards_accrued(
        alice: &signer,
        bob: &signer,
        cleo: &signer, 
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let bob_addr = signer::address_of(bob);
        let cleo_addr = signer::address_of(cleo);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        let pre_balance_bob = coin::balance<AptosCoin>(bob_addr);
        let pre_balance_cleo = coin::balance<AptosCoin>(cleo_addr);

        // distribute rewards
        distribute_all(alice, true);

        let post_balance_bob = coin::balance<AptosCoin>(bob_addr);
        let post_balance_cleo = coin::balance<AptosCoin>(cleo_addr);

        assert!(pre_balance_bob == post_balance_bob, 0);
        assert!(pre_balance_cleo == post_balance_cleo, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_all_in_truapt(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);
        let cleo_addr = signer::address_of(cleo);
        let treasury_addr = signer::address_of(treasury);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // distribute rewards
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_alice = truAPT::balance_of(alice_addr);
        let pre_balance_cleo = truAPT::balance_of(cleo_addr);
        let pre_balance_treasury = truAPT::balance_of(treasury_addr);

        distribute_all(alice, false);
        
        let post_balance_bob = truAPT::balance_of(bob_addr);
        let post_balance_alice = truAPT::balance_of(alice_addr);
        let post_balance_cleo = truAPT::balance_of(cleo_addr);
        let post_balance_treasury = truAPT::balance_of(treasury_addr);

        let (share_price_num, share_price_denom) = staker::share_price();
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;
        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;

        // check truAPT balance of recipient increased
        assert!((post_balance_bob - pre_balance_bob as u256) == distributed_truAPT_after_fees, 0);
        assert!((post_balance_cleo - pre_balance_cleo as u256) == distributed_truAPT_after_fees, 0);
        assert!((post_balance_alice as u256) + (distributed_truAPT_after_fees * 2) + (fees * 2) == (pre_balance_alice as u256), 0);
        assert!((post_balance_treasury as u256) == (pre_balance_treasury as u256) + (fees * 2), 0)
    }
   
   #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_all_in_apt(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);
        let cleo_addr = signer::address_of(cleo);
        let treasury_addr = signer::address_of(treasury);


        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // mint APT to distributor
        aptos_coin::mint(aptos_framework, alice_addr, 30 * constants::one_apt());
        
       // distribute all
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_alice = truAPT::balance_of(alice_addr);
        let pre_balance_cleo = truAPT::balance_of(cleo_addr);
        let pre_balance_treasury = truAPT::balance_of(treasury_addr);

        let pre_apt_balance_alice = coin::balance<AptosCoin>(alice_addr);
        let pre_apt_balance_bob = coin::balance<AptosCoin>(bob_addr);
        let pre_apt_balance_cleo = coin::balance<AptosCoin>(cleo_addr);

        distribute_all(alice, true);
        
        let (share_price_num, share_price_denom) = staker::share_price();
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;
        
        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;
        let distributed_APT_after_fees = (distributed_truAPT_after_fees as u256) * share_price_num / (share_price_denom * staker::share_price_scaling_factor());

        // check APT balance of recipient increased
        assert!((coin::balance<AptosCoin>(bob_addr) - pre_apt_balance_bob  as u256) == (distributed_APT_after_fees), 0);
        assert!((coin::balance<AptosCoin>(cleo_addr) - pre_apt_balance_cleo as u256) == (distributed_APT_after_fees), 0);

        // check APT balance of distributor decreased
        assert!((coin::balance<AptosCoin>(alice_addr) as u256) + (distributed_APT_after_fees * 2) == (pre_apt_balance_alice as u256), 0);

        // check truAPT balance of recipients remained the same, distributor decreased and treasury increased
        assert!(pre_balance_bob == truAPT::balance_of(bob_addr), 0);
        assert!(pre_balance_cleo == truAPT::balance_of(cleo_addr), 0);
        assert!((pre_balance_alice as u256) == (truAPT::balance_of(alice_addr) as u256) + (fees * 2), 0);
        assert!((pre_balance_treasury as u256) == (truAPT::balance_of(treasury_addr) as u256) - (fees * 2), 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_all_in_truapt_skipping_recipient_that_user_has_already_distributed_to(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);
        let cleo_addr = signer::address_of(cleo);
        let treasury_addr = signer::address_of(treasury);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // mint APT to distributor
        aptos_coin::mint(aptos_framework, alice_addr, 30 * constants::one_apt());

        distribute_rewards(alice, bob_addr, false);

       // distribute all
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_alice = truAPT::balance_of(alice_addr);
        let pre_balance_cleo = truAPT::balance_of(cleo_addr);
        let pre_balance_treasury = truAPT::balance_of(treasury_addr);

        distribute_all(alice, false);
        
        let (share_price_num, share_price_denom) = staker::share_price();
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;
        
        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;

        // check APT balance of distributor decreased (by half amount, 1 recipient skipped and fees)
        assert!((pre_balance_alice as u256) == (truAPT::balance_of(alice_addr) as u256) + fees + distributed_truAPT_after_fees, 0);
        // bob was already distributed to, hence no change in balance (skipped)
        assert!(pre_balance_bob == truAPT::balance_of(bob_addr), 0);
        // cleo was distributed to, hence increase in balance 
        assert!((pre_balance_cleo as u256) + distributed_truAPT_after_fees == (truAPT::balance_of(cleo_addr) as u256), 0);
        // treasury was minted fees for one distribution
        assert!((pre_balance_treasury as u256) == (truAPT::balance_of(treasury_addr) as u256) - fees, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_all_in_apt_skipping_recipient_that_user_has_already_distributed_to(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);
        let cleo_addr = signer::address_of(cleo);
        let treasury_addr = signer::address_of(treasury);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // mint APT to distributor
        aptos_coin::mint(aptos_framework, alice_addr, 30 * constants::one_apt());

        distribute_rewards(alice, bob_addr, true);

       // distribute all
        let pre_balance_bob = truAPT::balance_of(bob_addr);
        let pre_balance_alice = truAPT::balance_of(alice_addr);
        let pre_balance_cleo = truAPT::balance_of(cleo_addr);
        let pre_balance_treasury = truAPT::balance_of(treasury_addr);

        let pre_apt_balance_alice = coin::balance<AptosCoin>(alice_addr);
        let pre_apt_balance_bob = coin::balance<AptosCoin>(bob_addr);
        let pre_apt_balance_cleo = coin::balance<AptosCoin>(cleo_addr);

        distribute_all(alice, true);
        
        let (share_price_num, share_price_denom) = staker::share_price();
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;
        
        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;
        let distributed_APT_after_fees = (distributed_truAPT_after_fees as u256) * share_price_num / (share_price_denom * staker::share_price_scaling_factor());
        assert!(distributed_APT_after_fees != 0, 0);

        // check APT balance of distributor decreased (by half amount, 1 recipient skipped)
        assert!((coin::balance<AptosCoin>(alice_addr) as u256) + distributed_APT_after_fees == (pre_apt_balance_alice as u256), 0);
        // bob was already distributed to, hence no change in balance (skipped)
        assert!(coin::balance<AptosCoin>(bob_addr) == pre_apt_balance_bob, 0);
        // cleo was distributed to, hence increase in balance 
        assert!((coin::balance<AptosCoin>(cleo_addr) - pre_apt_balance_cleo as u256) == (distributed_APT_after_fees), 0);

        // check truAPT balance of recipient and distributor remained the same
        assert!(pre_balance_bob == truAPT::balance_of(bob_addr), 0);
        assert!(pre_balance_cleo == truAPT::balance_of(cleo_addr), 0);
        assert!((pre_balance_alice as u256) == (truAPT::balance_of(alice_addr) as u256) + fees, 0);
        assert!((pre_balance_treasury as u256) == (truAPT::balance_of(treasury_addr) as u256) - fees, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65542, location=coin)]
    public entry fun test_distribute_all_in_apt_fails_when_distributor_has_no_apt(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // distribute rewards fails with EINSUFFICIENT_BALANCE
        distribute_all(alice, true);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65540, location=fungible_asset)]
    public entry fun test_distribute_all_in_truapt_fails_when_distributor_has_no_truapt(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
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

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let balance = truAPT::balance_of(alice_addr);
        let truAPT_metadata = truAPT::get_metadata();
        primary_fungible_store::transfer(alice, truAPT_metadata, bob_addr, balance);
        
        distribute_all(alice, false); // fails with EINSUFFICIENT_BALANCE
    }

    #[test(alice=@0xE0A1, bob=@0x1288, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65540, location=fungible_asset)]
    public entry fun test_distribute_in_apt_fails_when_user_has_no_truapt(
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
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100*deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // stake some tokens with the default pool
        stake(alice, deposit_amount);

        staker::allocate(alice, signer::address_of(bob), deposit_amount);

        // accrue enough rewards such that total_staked exceeds tax exempt stake
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        assert!(staker::total_staked() > staker::tax_exempt_stake(), 0);

        // user withdraws everything they got (burns TruAPT)
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw);

        // User then wants to distribute rewards in APT (straight from wallet, balance is high enough) to another user
        // Fails with insufficient_balance in TruAPT to pay for distribution fees.
        staker::distribute_rewards(alice, signer::address_of(bob), true); // fails with EINSUFFICIENT_BALANCE
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65558, location=staker)]
    public entry fun test_distribute_all_fails_when_distributor_has_no_allocations(
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
        
        let distributor_address = signer::address_of(alice);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[distributor_address]);
        
        //stake
        stake(alice, deposit_amount);

        distribute_all(alice, false); // fails with ENO_ALLOCATION
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=65561, location=staker)]
    public entry fun test_distribute_all_fails_for_fully_deallocated_recipients_only(
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
        
        let distributor_address = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[distributor_address]);
        
        //stake
        stake(alice, deposit_amount);

        allocate(alice, bob_addr, deposit_amount/2);

        deallocate(alice, bob_addr, deposit_amount/2);

        distribute_all(alice, false);  // fails with ENO_ALLOCATION_TO_RECIPIENT
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    #[expected_failure(abort_code=327708, location=staker)]
    public entry fun test_distribute_all_when_paused_fails(
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
        
        let distributor_address = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // whitelist and setup user with APT
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[distributor_address]);
        
        //stake
        stake(alice, deposit_amount);

        allocate(alice, bob_addr, deposit_amount/2);

        // pause staker
        staker::pause(admin);

        distribute_all(alice, false); // ECONTRACT_PAUSED
    }

    #[test(alice=@0xE0A1, bob=@0x1288, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_distribute_in_apt_after_leaving_minimum_stake_behind(
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
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100*deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // stake some tokens with the default pool
        stake(alice, deposit_amount);

        staker::allocate(alice, signer::address_of(bob), deposit_amount);

        // Accrue enough rewards such that total staked exceeds tax exempt stake
        let i = 0;
        while (i < 100){
            delegation_pool::end_aptos_epoch();
            i = i + 1;
        };

        // withdraw everything minus minimum stake amount
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw-10*constants::one_apt());

        let alice_truAPT_balance = truAPT::balance_of(signer::address_of(alice));
        // successfully distributes rewards in APT, pays for distribution fees with remaining TruAPT min stake amount
        staker::distribute_rewards(alice, signer::address_of(bob), true);
        let alice_truAPT_balance_after_distribution = truAPT::balance_of(signer::address_of(alice));

        assert!(alice_truAPT_balance_after_distribution < alice_truAPT_balance, 0);
        assert!(alice_truAPT_balance_after_distribution < constants::default_min_deposit(), 0);
    }

    //  _____________________________ Event Emission Tests _____________________________

    #[test(alice=@0xE0A1B, bob=@0xABC123B, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DistributedRewardsEvent_emitted_when_distributing_truapt(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let bob_addr = signer::address_of(bob);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocation(alice, bob, aptos_framework, whitelist);
        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        distribute_rewards(alice, bob_addr, false);

        let (share_price_num, share_price_denom) = staker::share_price();

        // assert event values
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;

        let fees = (distributed_truAPT as u64) * constants::default_dist_fee() / constants::fee_precision() ;
        let distributed_truAPT_after_fees = distributed_truAPT - (fees as u256);
        let distributed_APT = (distributed_truAPT_after_fees as u256) * share_price_num / (share_price_denom * staker::share_price_scaling_factor());

        // assert number of emitted events
        let distribution_events = event::emitted_events<staker::DistributedRewardsEvent>();
        assert!(vector::length(&distribution_events) == 1, 0);

        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        let expected_event = staker::test_DistributedRewardsEvent(signer::address_of(alice), signer::address_of(bob), (distributed_truAPT_after_fees as u64), 
                                                                  (distributed_APT as u64), fees, share_price_num, share_price_denom, false, total_allocated_amount,
                                                                  total_allocated_share_price_num, total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
    
    #[test(alice=@0xE0A1B, bob=@0xABC123B, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DistributedRewardsEvent_emitted_when_distributing_apt(
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
        set_up_allocation(alice, bob, aptos_framework, whitelist);
        
        // mint APT to distributor
        aptos_coin::mint(aptos_framework, alice_addr, 30 * constants::one_apt());

        let (pre_share_price_num, pre_share_price_denom) = staker::share_price();

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        let pre_balance = coin::balance<AptosCoin>(bob_addr);
        distribute_rewards(alice, bob_addr, true);
        let post_balance = coin::balance<AptosCoin>(bob_addr);

        // assert number of emitted events
        let distribution_events = event::emitted_events<staker::DistributedRewardsEvent>();
        assert!(vector::length(&distribution_events) == 1, 0);

        // assert event values
        let (share_price_num, share_price_denom) = staker::share_price();
        
        let distributed_APT = post_balance - pre_balance;
        
        let lhs = ((50 * constants::one_apt()) as u256) * pre_share_price_denom * (constants::one_apt() as u256) / pre_share_price_num;
        let rhs = ((50 * constants::one_apt()) as u256) * share_price_denom * (constants::one_apt() as u256) / share_price_num;
        let distributed_truAPT = lhs - rhs;
        let fees = distributed_truAPT * (constants::default_dist_fee() as u256) / (constants::fee_precision() as u256);
        let distributed_truAPT_after_fees = distributed_truAPT - fees;
        let (total_allocated_amount, total_allocated_share_price_num, total_allocated_share_price_denom) = staker::total_allocated(signer::address_of(alice));

        let expected_event = staker::test_DistributedRewardsEvent(signer::address_of(alice), signer::address_of(bob), (distributed_truAPT_after_fees as u64), 
                                                                  distributed_APT, (fees as u64), share_price_num, share_price_denom, true, total_allocated_amount, 
                                                                  total_allocated_share_price_num, total_allocated_share_price_denom);
        assert!(event::was_event_emitted(&expected_event), 0);
    }

    #[test(alice=@0xE0A1B, bob=@0xABC123B, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DistributedAllEvent_emitted_when_distributing_truapt(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        distribute_all(alice, false);

        // assert number of emitted events
        let distribution_events = event::emitted_events<staker::DistributedAllEvent>();
        assert!(vector::length(&distribution_events) == 1, 0);

        let expected_event = staker::test_DistributedAllEvent(signer::address_of(alice));
        assert!(event::was_event_emitted(&expected_event), 0);
    }
    
    #[test(alice=@0xE0A1B, bob=@0xABC123B, cleo=@0xFAB123, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_DistributedAllEvent_emitted_when_distributing_apt(
        alice: &signer,
        bob: &signer,
        cleo: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        let alice_addr = signer::address_of(alice);

        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        set_up_allocations(alice, bob, cleo, aptos_framework, whitelist);
        
        // mint APT to distributor
        aptos_coin::mint(aptos_framework, alice_addr, 30 * constants::one_apt());

        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        distribute_all(alice, true);

        // assert number of emitted events
        let distribution_events = event::emitted_events<staker::DistributedAllEvent>();
        assert!(vector::length(&distribution_events) == 1, 0);

        let expected_event = staker::test_DistributedAllEvent(signer::address_of(alice));
        assert!(event::was_event_emitted(&expected_event), 0);
    }
}