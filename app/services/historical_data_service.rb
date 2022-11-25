class HistoricalDataService
  def get_data(pair, pair_length = 3)
    File.write "#{pair}.csv", HTTPX.get("https://www.cryptodatadownload.com/cdd/Binance_#{pair}_1h.csv").read
    file = File.open "#{pair}.csv"
    file.gets # read the first line, but ignore it since it contains non-CSV data
    File.write "#{pair}_data.csv", file.read
    file.close
    File.delete "#{pair}.csv"
    load_data(pair, pair_length)
  end

  def load_data(pair, pair_length = 3)
    df = Rover.read_csv("#{pair}_data.csv")
    ['unix', 'symbol', 'Volume USDT', 'tradecount'].each { |i| df.delete(i) }
    df.rename(
      'date' => :datetime,
      'open' => :open,
      'high' => :high,
      'low' => :low,
      'close' => :close,
      "Volume #{pair[0..pair_length-1]}" => :volume
    )
    df[:datetime] = df[:datetime].map do |i| 
      begin
        Time.strptime(i + ' utc', '%Y-%m-%d %I-%p %z')
      rescue
        i.to_datetime
      end
    end
    df = get_today_historical(pair).concat df
    df.sort_by! { |r| r[:datetime] }
  end

  def get_today_historical(pair)
    url = 'https://api.binance.com/api/v1/klines' +'?symbol=' + pair + '&interval=' + '1h' + '&startTime=' + (Date.current.to_datetime.to_i*1000).to_s
    page = HTTPX.get(url)
    columns = [:datetime, :open, :high, :low, :close, :volume]
    data = page.json.map do |i|
      e = {}
      columns.each do |name|
        e[name] = i.shift
      end
      e
    end
    df = Rover::DataFrame.new data
    df[:datetime] = df[:datetime].map { |i| Time.at(i/1000).utc }
    [:open, :high, :low, :close, :volume].each { |i| df[i] = df[i].map(&:to_f) }
    df
  end

end