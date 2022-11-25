class Strategies::Advanced
  attr_accessor :df, :support, :resist

  def initialize(data)
    @df = data
    df[:candle_size] = df[:high] - df[:low]
    df[:candle_size_ma] = 0.0
    df[:direction] = ''

    (24..df.size-1).each do |i|
      df[:candle_size_ma][i] = df[:candle_size][i-24..i].mean
      df[:direction][i] = df[:close][i] > df[:open][i] ? 'bull' : 'bear'
    end
    df
  end

  def daily_range(part_df)
    part_df[:day] = part_df[:datetime].map{|i| i.to_date}
    a = part_df.group(:day).min(:low)
    b = part_df.group(:day).max(:high)
    c = a.left_join(b, on: :day)
    c.last(10)
    (c['max_high'] - c['min_low']).mean
  end

  def volume_profile(plot = false)
    _df = df.dup
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
    candle_size_mult = 3
    daily_range_mult = 3

    up_top = 0
    dwn_bot = 0
    up_start = dwn_start = nil
    break_counter = 0

    @support = []
    @resist = []
    error_i = []
    up_idx = dwn_idx = nil

    (50..df.count-25).each do |i|
      # Up
      if break_counter == 0 && df[:candle_size][i] >= df[:candle_size_ma][i] * candle_size_mult && \
        (df[:open][i] - df[:close][i]).abs / df[:candle_size][i] * 100 >= 50 && \
        df[:open][i] <= df[:close][i] && df[:open][i] < df[:high][i+1..i+23].min
    
        up_idx = if df[:direction][i] == df[:direction][i-1]
          i - 1 - (df[i-48..i-1][:direction] != df[:direction][i]).to_a.reverse.index(true)
        else
          i
        end
        up_start = df[:open][up_idx]
        up_top = df[:high][up_idx]
        break_counter = 1
      end
      if up_top > 0 && df[:high][i] > up_top
        up_top = df[:high][i]
      end
      if up_idx && up_start && up_top > 0 && (up_top - df[:low][i]).abs / (up_top - up_start) > 0.5 && \
        (up_top - up_start) >= daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1]) || \
        up_idx && up_top > 0 && (up_top - up_start).abs >= daily_range_mult * daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1])
    
        price = volume_profile(df[up_idx-24..up_idx])[0][:close].to_a.sort_by {|i| (i-up_start).abs}.first
        @support << {
          'Added' => up_idx,
          'Price' => price,
          'SL' => (price - df[up_idx-24..up_idx][:low].min).abs,
          'Type' => 'support',
          'Tested' => 0
        }
        break_counter, up_top = 0, 0
      end
      if up_start && up_top > 0 && df[:low][i] < up_start
        break_counter, up_top = 0, 0
      end
    
      # Down
      if break_counter == 0 && df[:candle_size][i] >= df[:candle_size_ma][i] * candle_size_mult && \
        (df[:open][i] - df[:close][i]).abs / df[:candle_size][i] * 100 >= 50 && \
        df[:open][i] >= df[:close][i] && df[:open][i] > df[:low][i+1..i+23].max
    
        dwn_idx = if df[:direction][i] == df[:direction][i-1]
          i - 1 - (df[i-48..i-1][:direction] != df[:direction][i]).to_a.reverse.index(true)
        else
          i
        end
        dwn_start = df[:open][dwn_idx]
        dwn_bot = df[:low][dwn_idx]
        break_counter = 1
      end
      if dwn_bot > 0 && df[:low][i] < dwn_bot
        dwn_bot = df[:low][i]
      end
      if dwn_idx && dwn_start && dwn_bot > 0 && (dwn_bot - df[:high][i]).abs / (dwn_bot - dwn_start) > 0.5 && \
        (dwn_bot - dwn_start) >= daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1]) || \
        dwn_idx && dwn_bot > 0 && (dwn_bot - dwn_start).abs >= daily_range_mult * daily_range(df[(i-240 > 0 ? i-240 : 0)..i-1])
    
        price = volume_profile(df[dwn_idx-24..dwn_idx])[0][:close].to_a.sort_by {|i| (i-dwn_start).abs}.first
        @resist << {
          'Added' => dwn_idx,
          'Price' => price,
          'SL' => (price - df[dwn_idx-24..dwn_idx][:high].max).abs,
          'Type' => 'resist',
          'Tested' => 0,
          'DownStart' => dwn_start
        }
        break_counter, dwn_bot = 0, 0
      end
      if dwn_start && dwn_bot > 0 && df[:high][i] > dwn_start
        break_counter, dwn_bot = 0, 0
      end
    end
  end

end