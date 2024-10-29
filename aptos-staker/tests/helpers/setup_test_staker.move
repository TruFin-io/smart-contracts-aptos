
#[test_only]
module publisher::setup_test_staker {
    use std::string::{String, utf8};
    use std::signer;

    use aptos_framework::account;
    use aptos_framework::aptos_coin;

    // smart contracts
    use publisher::staker::{Self, test_initialize};
    use whitelist::master_whitelist;

    // test modules
    use publisher::account_setup;
    use publisher::constants;
    use publisher::setup_test_delegation_pool;

    friend publisher::init_test;
    friend publisher::setter_test;
    friend publisher::stake_test;
    friend publisher::unlock_test;
    friend publisher::withdraw_test;
    friend publisher::share_price_test;
    friend publisher::total_staked_test;
    friend publisher::getter_test;
    friend publisher::fees_test;
    friend publisher::residual_rewards_test;
    friend publisher::withdraw_list_test;

    // _____________________________ Set up _____________________________
        
    public fun setup(admin: &signer, resource_account: &signer, src: &signer): address {
        let framework = account::create_account_for_test(@0x1);
        return setup_with_delegation_pool(&framework, admin, resource_account, src, src)
    }

    // function to whitelist the whitelist owner and stake minimum to staker
    public fun initial_deposit(aptos_framework: &signer, whitelist_owner: &signer, delegation_pool: address){
        let deposit_amount = 11 * constants::one_apt();
        master_whitelist::whitelist_user(whitelist_owner, signer::address_of(whitelist_owner));
        aptos_coin::mint(aptos_framework, signer::address_of(whitelist_owner), deposit_amount);
        staker::stake_to_specific_pool(whitelist_owner, deposit_amount, delegation_pool);
    }

    public fun setup_with_delegation_pool(
        aptos_framework: &signer, 
        admin: &signer, 
        resource_account: &signer, 
        src: &signer, 
        validator: &signer
        ): address {
        account::create_account_for_test(@0x1);
        setup_test_delegation_pool::setup(aptos_framework);

        account_setup::create_main_accounts(admin, resource_account, src);
        test_initialize(resource_account);

        let delegation_pool = setup_test_delegation_pool::create_basic_pool(validator);
        init_staker(admin, delegation_pool);
        return delegation_pool
    }

    fun init_staker(admin: &signer, delegation_pool: address) {
        let name: String = utf8(b"Trufin aptos staker v1");
        staker::initialize(
            admin,
            name,
            @0x122,
            delegation_pool,
            constants::default_fee(),
            constants::default_dist_fee(),
            constants::default_min_deposit()
        );
    }
 }