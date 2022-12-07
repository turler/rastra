class Strategies::Advanced
  attr_accessor :df, :support, :resist, :pair, :is_handling, :used_support, :used_resistance
  attr_accessor :open_trades, :closed_profits, :closed_losses, :capital, :slippage, :rr_coef
  attr_accessor :candle_size_mult, :daily_range_mult, :retry_times

  def initialize(pair, pair_length = 3)
    stra_logger.info("Initialize strategy advanced")

    return if pair.blank?

    @retry_times = 0

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
    @df[:candle_size] = @df[:high] - @df[:low]
    @df[:candle_size_ma] = 0.0
    @df[:direction] = ''

    (24..@df.size-1).each do |i|
      @df[:candle_size_ma][i] = @df[:candle_size][i-24..i].mean
      @df[:direction][i] = @df[:close][i] > @df[:open][i] ? 'bull' : 'bear'
    end
    stra_logger.info("Finding levels from data")
    find_or_load_levels
    stra_logger.info("Finding levels from data: DONE")
  end

  def stra_logger
    @@stra_logger ||= Logger.new("#{Rails.root}/log/advanced_stra.log")
  end

  def trade_logger
    @@trade_logger ||= Logger.new("#{Rails.root}/log/trades_stra.log")
  end

  def run(data)
    begin
      stra_logger.info('Handling ticker data')
      # Calculating data for current price
      stra_logger.info(data.inspect)
      @df = @df[@df[:datetime] != data[0][:datetime]]
      last_df = Rover::DataFrame.new data
      last_df[:candle_size] = last_df[:high] - last_df[:low]
      last_df[:candle_size_ma] = df.last(23).concat(last_df)[:candle_size].mean
      last_df[:direction] = last_df[:close][0] > last_df[:open][0] ? 'bull' : 'bear'
      puts 'Last DF'
      puts last_df
      stra_logger.info("Latest DF: #{last_df}")
      @df.concat last_df
      level_added_count = find_level(df.count - 1)
      puts 'Addition level added count: ' +  level_added_count.to_s
      stra_logger.info("Addition level added count: #{level_added_count} at #{df.count - 1}")
      # Check buy/sell signal
      check_signal_trade(df.count - 1)
      stra_logger.info('Check signal trade DONE')
      @retry_times = 0
      return @retry_times
    rescue e => message
      stra_logger.info('Handle ticker data with error')
      stra_logger.info(message)
      @retry_times += 1
      return @retry_times
    end
  end

  def backtest
    (50..@df.count-25).each do |i|
      check_signal_trade(i)
    end
  end

  def check_signal_trade(i)
    puts 'Check signal trade at ' + i.to_s
    stra_logger.info("Check signal trade at #{i}")

    #*******************************************Short*******************************************
    if @resist.present?
      closest_resistance = @resist[(@resist['Added'] <= i - 1) & (@resist['Price'] > df[:high][i-1])].sort_by! { |r| r['Price'] }.first
    end
    # Entry
    if @open_trades.blank? && !closest_resistance.blank? && df[:high][i-1] < closest_resistance['Price'][0] && df[:high][i] >= closest_resistance['Price'][0]
      puts "Short trade: #{i} | #{df[i][:datetime][0]} Levels added: #{closest_resistance['Added'][0]}"
      @open_trades << {
        'price': closest_resistance['Price'][0] - (df[:candle_size][i] * slippage),
        'level_added': closest_resistance['Added'][0],
        'trade_open': i,
        'trade_close': 0,
        'result': 0,
        'direction': 'Sell',
        'TP': closest_resistance['Price'][0] - (rr_coef * closest_resistance['SL'][0]),
        'SL': closest_resistance['Price'][0] + closest_resistance['SL'][0]
      }.transform_keys(&:to_s)
      stra_logger.info("Open short trade: #{@open_trades.last.inspect}")
      trade_logger.info("Open short trade: #{@open_trades.last.inspect}")
      # Remove level
      if df[:high][i] >= closest_resistance['Price'][0] && closest_resistance['Tested'][0] == 0
        @resist = @resist[@resist['Added'] != closest_resistance['Added'][0]]
        closest_resistance['Tested'][0] = i
        @used_resistance << closest_resistance
        stra_logger.info("Move tested @resist level to used: #{closest_resistance.to_s}")
      end
    end

    # Manage trades
    if @open_trades.size > 0
      current_trade = @open_trades[-1]
      if current_trade['direction'] == 'Sell'
        # SL
        if df[:high][i] >= current_trade['SL']
          current_trade['result'] = (current_trade['price'] - current_trade['SL']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          @closed_losses << current_trade
          @open_trades.delete(current_trade)
          puts "SL #{i} -with result: #{current_trade['result'].round(1)}"
          stra_logger.info("Stop loss sell position trigger: #{current_trade.inspect}")
          trade_logger.info("Stop loss sell position trigger: #{current_trade.inspect}")
          # Draw
          return
        end
        # TP
        if df[:low][i] <= current_trade['TP']
          current_trade['result'] = (current_trade['price'] - current_trade['TP']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          @closed_profits << current_trade
          @open_trades.delete(current_trade)
          puts "TP #{i} -with result: #{current_trade['result'].round(1)}"
          stra_logger.info("Take profit sell position trigger: #{current_trade.inspect}")
          trade_logger.info("Take profit sell position trigger: #{current_trade.inspect}")
          # Draw
          return
        end
      end
    end
    #*******************************************Long*******************************************
    if @support.present?
      closest_support = @support[(@support['Added'] <= i - 1) & (@support['Price'] < df[:low][i-1])].sort_by! { |r| r['Price'] }.last
    end
    # Entry
    if @open_trades.blank? && !closest_support.blank? && df[:low][i-1] > closest_support['Price'][0] && df[:low][i] <= closest_support['Price'][0]
      puts "Long trade: #{i} Levels added: #{closest_support['Added'][0]}"
      @open_trades << {
        'price': closest_support['Price'][0] + (df[:candle_size][i] * slippage),
        'level_added': closest_support['Added'][0],
        'trade_open': i,
        'trade_close': 0,
        'result': 0,
        'direction': 'Buy',
        'TP': closest_support['Price'][0] + (rr_coef * closest_support['SL'][0]),
        'SL': closest_support['Price'][0] - closest_support['SL'][0]
      }.transform_keys(&:to_s)
      stra_logger.info("Open long trade: #{@open_trades.last.inspect}")
      trade_logger.info("Open long trade: #{@open_trades.last.inspect}")
      # Remove level
      if df[:low][i] <= closest_support['Price'][0] && closest_support['Tested'][0] == 0
        @support = @support[@support['Added'] != closest_support['Added'][0]]
        closest_support['Tested'][0] = i
        @used_support << closest_support
        stra_logger.info("Move tested @support level to used: #{closest_support.to_s}")
      end
    end

    # Manage trades
    if @open_trades.size > 0
      current_trade = @open_trades[-1]
      if current_trade['direction'] == 'Buy'
        # SL
        if df[:low][i] <= current_trade['SL']
          current_trade['result'] = (current_trade['SL'] - current_trade['price']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          @closed_losses << current_trade
          @open_trades.delete(current_trade)
          puts "SL #{i} -with result: #{current_trade['result'].round(1)}"
          stra_logger.info("Stop loss long position trigger: #{current_trade.inspect}")
          trade_logger.info("Stop loss long position trigger: #{current_trade.inspect}")
          # Draw
          return
        end
        # TP
        if df[:high][i] >= current_trade['TP']
          current_trade['result'] = (current_trade['TP'] - current_trade['price']) * (capital / df[:close][i])
          current_trade['trade_close'] = i

          @closed_profits << current_trade
          @open_trades.delete(current_trade)
          puts "TP #{i} -with result: #{current_trade['result'].round(1)}"
          stra_logger.info("Take profit long position trigger: #{current_trade.inspect}")
          trade_logger.info("Take profit long position trigger: #{current_trade.inspect}")
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

    @support = Rover::DataFrame.new
    @resist = Rover::DataFrame.new

    (50..df.count-25).each do |i|
      find_level(i)
    end
  end

  def find_level(i)
    # Up
    added_count = 0
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
      @support.concat Rover::DataFrame.new([{
        'Added' => @up_idx,
        'i' => i,
        'Price' => price,
        'SL' => (price - df[@up_idx-24..@up_idx][:low].min).abs,
        'Type' => 'support',
        'Tested' => 0
      }])
      stra_logger.info("Support added: #{@support.last.inspect}")
      added_count += 1
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
      @resist.concat Rover::DataFrame.new({
        'Added' => @dwn_idx,
        'i' => i,
        'Price' => price,
        'SL' => (price - df[@dwn_idx-24..@dwn_idx][:high].max).abs,
        'Type' => 'resist',
        'Tested' => 0,
        'DownStart' => @dwn_start
      }])
      stra_logger.info("Resist added: #{@resist.last.inspect}")
      added_count += 1
      @break_counter, @dwn_bot = 0, 0
    end
    if @dwn_start && @dwn_bot > 0 && df[:high][i] > @dwn_start
      @break_counter, @dwn_bot = 0, 0
    end
    added_count
  end

end
