class Strategies::Advanced
  attr_accessor :df, :support, :resist, :pair, :is_handling, :used_support, :used_resistance
  attr_accessor :open_trades, :closed_profits, :closed_losses, :capital, :slippage, :rr_coef
  attr_accessor :candle_size_mult, :daily_range_mult

  def initialize(pair, pair_length = 3)
    return if pair.blank?

    @candle_size_mult = 3
    @daily_range_mult = 3

    @used_support = []
    @used_resistance = []
    @open_trades = []
    @closed_profits = []
    @closed_losses = []

    @capital = 10000
    @slippage = 0.01
    @rr_coef = 1

    @pair = pair
    @pair_length = pair_length
    @df = HistoricalDataService.new.load_data(pair, pair_length)
    df[:candle_size] = df[:high] - df[:low]
    df[:candle_size_ma] = 0.0
    df[:direction] = ''

    (24..df.size-1).each do |i|
      df[:candle_size_ma][i] = df[:candle_size][i-24..i].mean
      df[:direction][i] = df[:close][i] > df[:open][i] ? 'bull' : 'bear'
    end
    find_or_load_levels
  end

  def time_test
    @is_handling = true
    sleep 10
    @is_handling = false
  end

  def run(ticker_data)
    data = JSON.parse(ticker_data)
    # Calculating data for current price
    data = [{
      datetime: Time.at(data['E'].to_i/1000).utc,
      open: data['k']['o'].to_f,
      close: data['k']['c'].to_f,
      high: data['k']['h'].to_f,
      volume: data['k']['v'].to_f,
    }]
    last_df = Rover::DataFrame.new data
    last_df[:candle_size] = last_df[:high] - last_df[:low]
    last_df[0][:candle_size_ma] = df.last(23).concat(last_df)[:candle_size].mean
    df.concat last_df
    # Reset stat and Check if level can be added at this price
    @up_top = 0
    @dwn_bot = 0
    @up_start = @dwn_start = nil
    @up_idx = @dwn_idx = nil
    @break_counter = 0
    find_level(df.count - 1)
    # Check buy/sell signal
    check_signal_trade(df.count - 1)
    # remove temp last df from df if last df is not actually close kline
    df = df[df[:datetime] != last_df[:datetime][0]] unless data['k']['x']
  end

  def check_signal_trade(i)
    resistance = Rover::DataFrame.new resist
    support = Rover::DataFrame.new support

    #*******************************************Short*******************************************
    closest_resistance = resistance[(resistance['Added'] <= i - 1) & (resistance['Price'] > df[:high][i-1])].sort_by! { |r| r['Price'] }.first
    # Entry
    if open_trades.blank? && !closest_resistance.blank? && df[:high][i-1] < closest_resistance['Price'] && df[:high][i] >= closest_resistance['Price']
      puts "Short trade: #{i} | #{df[i][:datetime][0]} Levels added: #{closest_resistance['Added'][0]}"
      open_trades << {
        'price': closest_resistance['Price'][0] - (df[:candle_size][i] * slippage),
        'level_added': closest_resistance['Added'][0],
        'trade_open': i,
        'trade_close': 0,
        'result': 0,
        'direction': 'Sell',
        'TP': closest_resistance['Price'][0] - (rr_coef * closest_resistance['SL'][0]),
        'SL': closest_resistance['Price'][0] + closest_resistance['SL'][0]
      }.transform_keys(&:to_s)
      # Remove level
      if df[:high][i] >= closest_resistance['Price'] && closest_resistance['Tested'] == 0
        resistance = resistance[resistance['Added'] != closest_resistance['Added'][0]]
        closest_resistance['Tested'] = i
        used_resistance << closest_resistance
      end
    end

    # Manage trades
    if open_trades.size > 0
      current_trade = open_trades[-1]
      if current_trade['direction'] == 'Sell'
        # SL
        if df[:high][i] >= current_trade['SL']
          current_trade['result'] = (current_trade['price'] - current_trade['SL']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          closed_losses << current_trade
          open_trades.delete(current_trade)
          puts "SL #{i} -with result: #{current_trade['result'].round(1)}"
          # Draw
          return
        end
        # TP
        if df[:low][i] <= current_trade['TP']
          current_trade['result'] = (current_trade['price'] - current_trade['TP']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          closed_profits << current_trade
          open_trades.delete(current_trade)
          puts "TP #{i} -with result: #{current_trade['result'].round(1)}"
          # Draw
          return
        end
      end
    end
    #*******************************************Long*******************************************
    closest_support = support[(support['Added'] <= i - 1) & (support['Price'] < df[:low][i-1])].sort_by! { |r| r['Price'] }.last
    # Entry
    if open_trades.blank? && !closest_support.blank? && df[:low][i-1] > closest_support['Price'] && df[:low][i] <= closest_support['Price']
      puts "Long trade: #{i} Levels added: #{closest_support['Added'][0]}"
      open_trades << {
        'price': closest_support['Price'][0] + (df[:candle_size][i] * slippage),
        'level_added': closest_support['Added'][0],
        'trade_open': i,
        'trade_close': 0,
        'result': 0,
        'direction': 'Buy',
        'TP': closest_support['Price'][0] + (rr_coef * closest_support['SL'][0]),
        'SL': closest_support['Price'][0] - closest_support['SL'][0]
    }.transform_keys(&:to_s)
      # Remove level
      if df[:low][i] <= closest_support['Price'] && closest_support['Tested'] == 0
        support = support[support['Added'] != closest_support['Added'][0]]
        closest_support['Tested'] = i
        used_support << closest_support
      end
    end

    # Manage trades
    if open_trades.size > 0
      current_trade = open_trades[-1]
      if current_trade['direction'] == 'Buy'
        # SL
        if df[:low][i] <= current_trade['SL']
          current_trade['result'] = (current_trade['SL'] - current_trade['price']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          closed_losses << current_trade
          open_trades.delete(current_trade)
          puts "SL #{i} -with result: #{current_trade['result'].round(1)}"
          # Draw
          return
        end
        # TP
        if df[:high][i] >= current_trade['TP']
          current_trade['result'] = (current_trade['TP'] - current_trade['price']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          closed_profits << current_trade
          open_trades.delete(current_trade)
          puts "TP #{i} -with result: #{current_trade['result'].round(1)}"
          # Draw
          return
        end
      end
    end
  end

  def daily_range(part_df)
    part_df[:day] = part_df[:datetime].map{|i| Time.at(i/1000).to_date}
    a = part_df.group(:day).min(:low)
    b = part_df.group(:day).max(:high)
    c = a.left_join(b, on: :day)
    c.last(10)
    (c['max_high'] - c['min_low']).mean
  end

  def volume_profile(_df, plot = false)
    _df = _df.dup
    bucket_size = 0.002 * _df[:close].max
    _df[:close].map!{ |i| ((i/bucket_size).round(0)*bucket_size).round(5)}
    volprofile = _df.group(:close).sum(:volume)
    volprofile.rename('sum_volume' => :volume)
    volprofile.sort_by!{ |i| i[:close]}
    volprofile[:volume] = volprofile[:volume].round(6)
    vpoc = volprofile[:volume].max
    volume_nodes = volprofile.sort_by { |i| i[:volume]}.last(5)

    volprofile_copy = volprofile.dup
    total_volume = volprofile_copy.sum(:volume)
    value_area_volume = total_volume * 0.68

    val = 0
    vah = 0

    while value_area_volume >= 0 && volprofile.size > 100
      index_max = volprofile_copy[:volume].to_a.index(vpoc)
      two_above = index_max > 2 ? volprofile_copy[:volume][index_max-1] + volprofile_copy[:volume][index_max-2] : 0
      two_below = index_max > -2 ? volprofile_copy[:volume][index_max+1] + volprofile_copy[:volume][index_max+2] : 0
      val = volprofile_copy[:close][index_max-1]
      vah = volprofile_copy[:close][index_max+1]
      if two_above >= two_below
        volprofile_copy = volprofile_copy[!volprofile_copy[:volume].in?([volprofile_copy[:volume][index_max-1],volprofile_copy[:volume][index_max-2]])]
        value_area_volume = value_area_volume - two_above
      else
        volprofile_copy = volprofile_copy[!volprofile_copy[:volume].in?([volprofile_copy[:volume][index_max+1],volprofile_copy[:volume][index_max+2]])]
        value_area_volume = value_area_volume - two_below
      end
    end

    return [volume_nodes, val, vah, volprofile]
  end

  def find_or_load_levels
    @up_top = 0
    @dwn_bot = 0
    @up_start = @dwn_start = nil
    @up_idx = @dwn_idx = nil
    @break_counter = 0

    @support = []
    @resist = []

    (50..df.count-25).each do |i|
      find_level(i)
    end
  end

  def find_level(i)
    # Up
    if @break_counter == 0 && df[:candle_size][i] >= df[:candle_size_ma][i] * candle_size_mult && \
      (df[:open][i] - df[:close][i]).abs / df[:candle_size][i] * 100 >= 50 && \
      df[:open][i] <= df[:close][i] && df[:open][i] < df[:high][i+1..i+23].min

      @up_idx = if df[:direction][i] == df[:direction][i-1]
        i - 1 - (df[i-48..i-1][:direction] != df[:direction][i]).to_a.reverse.index(true)
      else
        i
      end
      @up_start = df[:open][@up_idx]
      @up_top = df[:high][@up_idx]
      @break_counter = 1
    end
    if @up_top > 0 && df[:high][i] > @up_top
      @up_top = df[:high][i]
    end
    if @up_idx && @up_start && @up_top > 0 && (@up_top - df[:low][i]).abs / (@up_top - @up_start) > 0.5 && \
      (@up_top - @up_start) >= daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1]) || \
      @up_idx && @up_top > 0 && (@up_top - @up_start).abs >= daily_range_mult * daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1])

      price = volume_profile(df[@up_idx-24..@up_idx])[0][:close].to_a.sort_by {|i| (i-@up_start).abs}.first
      @support << {
        'Added' => @up_idx,
        'Price' => price,
        'SL' => (price - df[@up_idx-24..@up_idx][:low].min).abs,
        'Type' => 'support',
        'Tested' => 0
      }
      @break_counter, @up_top = 0, 0
    end
    if @up_start && @up_top > 0 && df[:low][i] < @up_start
      @break_counter, @up_top = 0, 0
    end

    # Down
    if @break_counter == 0 && df[:candle_size][i] >= df[:candle_size_ma][i] * candle_size_mult && \
      (df[:open][i] - df[:close][i]).abs / df[:candle_size][i] * 100 >= 50 && \
      df[:open][i] >= df[:close][i] && df[:open][i] > df[:low][i+1..i+23].max

      @dwn_idx = if df[:direction][i] == df[:direction][i-1]
        i - 1 - (df[i-48..i-1][:direction] != df[:direction][i]).to_a.reverse.index(true)
      else
        i
      end
      @dwn_start = df[:open][@dwn_idx]
      @dwn_bot = df[:low][@dwn_idx]
      @break_counter = 1
    end
    if @dwn_bot > 0 && df[:low][i] < @dwn_bot
      @dwn_bot = df[:low][i]
    end
    if @dwn_idx && @dwn_start && @dwn_bot > 0 && (@dwn_bot - df[:high][i]).abs / (@dwn_bot - @dwn_start) > 0.5 && \
      (@dwn_bot - @dwn_start) >= daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1]) || \
      @dwn_idx && @dwn_bot > 0 && (@dwn_bot - @dwn_start).abs >= daily_range_mult * daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1])

      price = volume_profile(df[@dwn_idx-24..@dwn_idx])[0][:close].to_a.sort_by {|i| (i-@dwn_start).abs}.first
      @resist << {
        'Added' => @dwn_idx,
        'Price' => price,
        'SL' => (price - df[@dwn_idx-24..@dwn_idx][:high].max).abs,
        'Type' => 'resist',
        'Tested' => 0,
        'DownStart' => @dwn_start
      }
      @break_counter, @dwn_bot = 0, 0
    end
    if @dwn_start && @dwn_bot > 0 && df[:high][i] > @dwn_start
      @break_counter, @dwn_bot = 0, 0
    end
  end

end
