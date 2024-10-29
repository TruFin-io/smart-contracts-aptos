#[test_only]
module publisher::truAPT_test{
    use std::signer;

    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::object::{Object};
    use aptos_framework::primary_fungible_store;
    
    // smart contracts
    use publisher::staker::{test_initialize};
    use publisher::truAPT::{Self, get_metadata, burn, mint, total_supply};
    
    // test modules
    use publisher::account_setup::{create_main_accounts};

   fun setup_test(admin: &signer, resource_account: &signer, src: &signer){
        create_main_accounts(admin,resource_account,src);
        test_initialize(resource_account);
        truAPT::test_initialize(resource_account);
        
        let (admin_address, _, asset) = get_test_vars(admin, resource_account);

         // owner mints admin 200 truAPT
        mint(resource_account, admin_address, 200);
        assert!(primary_fungible_store::balance(admin_address, asset) == 200, 0);

    }

    fun get_test_vars(admin: &signer, resource_account: &signer):(address,address,Object<Metadata>){
        let admin_address = signer::address_of(admin);
        let owner_address = signer::address_of(resource_account);
        let asset = get_metadata();
        return (admin_address, owner_address, asset)
    }

    #[test(alice=@0xA11CE, owner = @publisher, src = @src_account)]
    fun test_basic_coin_flow_owner(
        alice: &signer,
        owner: &signer,
        src: &signer
    ) {
            
        setup_test(alice, owner, src);
        let (alice_address, owner_address, asset) = get_test_vars(alice, owner);
        
        // Alice starts with 200 TruAPT
        assert!(primary_fungible_store::balance(alice_address, asset) == 200, 0);

        // Owner mints themselves 100 TruAPT
        mint(owner, owner_address, 100);
        assert!(primary_fungible_store::balance(owner_address, asset) == 100, 0);
     
        // Owner transfers 10 TruAPT to Alice
        primary_fungible_store::transfer(owner, asset, alice_address, 10);
        assert!(primary_fungible_store::balance(owner_address, asset) == 90, 0);
        assert!(primary_fungible_store::balance(alice_address, asset) == 210, 0);

        // Owner withdraws 20 TruAPT from their account and then deposits them to Alice account
        let fa = primary_fungible_store::withdraw(owner, asset, 20);
        primary_fungible_store::deposit(alice_address, fa);
        assert!(primary_fungible_store::balance(owner_address, asset) == 70, 0);
        assert!(primary_fungible_store::balance(alice_address, asset) == 230, 0);

        // Owner can burn Alice's TruAPT
        burn(owner, alice_address, 80);
        assert!(primary_fungible_store::balance(alice_address, asset) == 150, 0)
    }

    #[test(admin = @default_admin, resource_account = @publisher, src = @src_account)]
    fun test_user_can_transfer(
        admin: &signer,
        resource_account: &signer,
        src: &signer) {
        setup_test(admin,resource_account,src);
        let (_, owner_address, asset) = get_test_vars(admin, resource_account);
        
        // admin transfers 50 truAPT to owner
        primary_fungible_store::transfer(admin, asset, owner_address, 50);
        assert!(primary_fungible_store::balance(owner_address, asset) == 50, 0);
    }
    
    #[test(admin = @default_admin, resource_account = @publisher, src = @src_account)]
    #[expected_failure(abort_code=327681,location=publisher::truAPT)]
    fun test_non_owner_mint_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer) {
        setup_test(admin,resource_account,src);

        // admin tries to mint 10 truAPT to themselves
        mint(admin, signer::address_of(admin), 10);
    }
    
    #[test(admin = @default_admin, resource_account = @publisher, src = @src_account)]
    #[expected_failure(abort_code=327681,location=publisher::truAPT)]
    fun test_non_owner_burn_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer) {
        setup_test(admin,resource_account,src);

        // admin tries to burn 10 truAPT 
        burn(admin, signer::address_of(admin),  10);
    }
   
    #[test(admin = @default_admin, resource_account = @publisher, src = @src_account)]
    fun test_total_supply(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test(admin,resource_account,src);
        let supply = total_supply();

        assert!(supply == 200, 0);
    }
}