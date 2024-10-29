#[test_only]
module publisher::time {
    use aptos_framework::delegation_pool;
    use aptos_framework::timestamp;

    use publisher::constants;

    // moves time and epoch forward for the default pool
    public fun move_olc_and_epoch_forward(){
        timestamp::fast_forward_seconds(constants::new_olc_period());
        delegation_pool::end_aptos_epoch();
    }
}