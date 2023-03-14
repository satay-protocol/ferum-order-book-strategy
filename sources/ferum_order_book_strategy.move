module satay_ferum_automated::ferum_order_book_strategy {

    use std::signer;

    use std::option;

    use aptos_framework::coin::{Self, Coin};

    use satay_coins::strategy_coin::StrategyCoin;

    use satay::math;
    use satay::satay;
    use satay::strategy_config;

    use ferum::market;

    struct FerumMarket<phantom StakeCoin, phantom RewardCoin> has drop {}

    struct TendLock<phantom StakeCoin, phantom RewardCoin> {
        protocol_addr: address
    }

    // governance functions

    public entry fun initialize<StakeCoin, RewardCoin>(governance: &signer) {
        satay::new_strategy<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(
            governance,
            FerumMarket<StakeCoin, RewardCoin> {}
        );
    }

    public fun open_for_tend<StakeCoin, RewardCoin>(
        strategy_manager: &signer,
        protocol_addr: address
    ): (Coin<RewardCoin>, TendLock<StakeCoin, RewardCoin>) {
        strategy_config::assert_strategy_manager<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(
            strategy_manager,
            get_strategy_account_address<StakeCoin, RewardCoin>()
        );

        let strategy_signer = &satay::strategy_signer<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(FerumMarket<StakeCoin, RewardCoin> {});
        let reward_balance = (market::view_market_account<StakeCoin, RewardCoin>(protocol_addr, address_of(strategy_signer))).quoteBalance;

        market::withdraw_from_market_account_entry<StakeCoin, RewardCoin>(
            strategy_signer,
            0,
            reward_balance
        );

        (coin::withdraw<RewardCoin>(strategy_signer, reward_balance), TendLock<StakeCoin, RewardCoin> { protocol_addr })
    }

    public fun close_for_tend<StakeCoin, RewardCoin>(
        stake_coins: Coin<StakeCoin>,
        tend_lock: TendLock<StakeCoin, RewardCoin>,
    ) {
        let strategy_signer = &satay::strategy_signer<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(FerumMarket<StakeCoin, RewardCoin> {});
        let stake_coin_value = coin::value(&stake_coins);

        coin::deposit<StakeCoin>(address_of(strategy_signer), stake_coins);
        market::deposit_to_market_account_entry<StakeCoin, RewardCoin>(strategy_signer, 0, stake_coin_value);
    }

    public entry fun deposit<StakeCoin, RewardCoin>(user: &signer, amount: u64, protocol_addr: address) {
        let base_coins = coin::withdraw<StakeCoin>(user, amount);
        let strategy_coins = apply<StakeCoin, RewardCoin>(base_coins, protocol_addr);
        if(!coin::is_account_registered<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>>(signer::address_of(user))) {
            coin::register<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>>(user);
        };
        coin::deposit(signer::address_of(user), strategy_coins);
    }

    public entry fun withdraw<StakeCoin, RewardCoin>(user: &signer, amount: u64, protocol_addr: address) {
        let strategy_coins = coin::withdraw<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>>(user, amount);
        let aptos_coins = liquidate<StakeCoin, RewardCoin>(strategy_coins, protocol_addr);
        coin::deposit(signer::address_of(user), aptos_coins);
    }

    public fun apply<StakeCoin, RewardCoin>(
        base_coins: Coin<StakeCoin>,
        protocol_addr: address
    ): Coin<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>> {
        let strategy_signer = &satay::strategy_signer<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(FerumMarket<StakeCoin, RewardCoin> {});
        let base_coin_value = coin::value(&base_coins);

        coin::deposit<StakeCoin>(address_of(strategy_signer), base_coins);
        market::deposit_to_market_account_entry<StakeCoin, RewardCoin>(strategy_signer, 0, stake_coin_value);

        satay::strategy_mint<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(
            calc_product_coin_amount<StakeCoin, RewardCoin>(base_coin_value, protocol_addr),
            FerumMarket<StakeCoin, RewardCoin> {}
        )
    }

    public fun liquidate<StakeCoin, RewardCoin>(
        strategy_coins: Coin<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>>,
        protocol_addr: address
    ): Coin<StakeCoin> {
        let strategy_signer = &satay::strategy_signer<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(FerumMarket<StakeCoin, RewardCoin> {});
        let strategy_coin_value = coin::value(&strategy_coins);
        let base_coin_value = calc_base_coin_amount<StakeCoin, RewardCoin>(strategy_coin_value, protocol_addr);

        market::withdraw_from_market_account_entry<StakeCoin, RewardCoin>(
            strategy_signer,
            base_coin_value,
            0
        );

        coin::withdraw<StakeCoin>(strategy_signer, base_coin_value)
    }

    public fun calc_base_coin_amount<StakeCoin, RewardCoin>(strategy_coin_amount: u64, protocol_addr: address): u64 {
        let strategy_signer = &satay::strategy_signer<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(FerumMarket<StakeCoin, RewardCoin> {});
        let base_coin_balance = (market::view_market_account<StakeCoin, RewardCoin>(protocol_addr, address_of(strategy_signer))).instrumentBalance;
        let strategy_coin_supply_option = coin::supply<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>>();
        let strategy_coin_supply = option::get_with_default(&strategy_coin_supply_option, 0);

        if(strategy_coin_supply == 0) {
            return base_coin_balance
        };
        math::calculate_proportion_of_u64_with_u128_denominator(
            base_coin_balance,
            strategy_coin_amount,
            strategy_coin_supply,
        )
    }

    public fun calc_product_coin_amount<StakeCoin, RewardCoin>(base_coin_amount: u64, protocol_addr: address): u64 {
        let strategy_signer = &satay::strategy_signer<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>(FerumMarket<StakeCoin, RewardCoin> {});
        let base_coin_balance = (market::view_market_account<StakeCoin, RewardCoin>(protocol_addr, address_of(strategy_signer))).instrumentBalance;
        let strategy_coin_supply_option = coin::supply<StrategyCoin<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>>();

        if(base_coin_balance == 0) {
            return base_coin_amount
        };
        math::mul_u128_u64_div_u64_result_u64(
            option::get_with_default(&strategy_coin_supply_option, 0),
            base_coin_amount,
            base_coin_balance,
        )
    }

    public fun get_strategy_account_address<StakeCoin, RewardCoin>(): address
    {
        satay::get_strategy_address<StakeCoin, FerumMarket<StakeCoin, RewardCoin>>()
    }

    public(friend) fun get_strategy_witness<StakeCoin, RewardCoin>(): FerumMarket<StakeCoin, RewardCoin> {
        FerumMarket<StakeCoin, RewardCoin> {}
    }
}