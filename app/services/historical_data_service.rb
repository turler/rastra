class HistoricalDataService
  def get_data(pair, pair_length = 3)
    File.write "#{pair}.csv", HTTPX.get("https://www.cryptodatadownload.com/cdd/Binance_#{pair}_1h.csv").read
    file = File.open "#{pair}.csv"
    file.gets # read the first line, but ignore it since it contains non-CSV data
    File.write "#{pair}_data.csv", file.read
    file.close
    File.delete "#{pair}.csv"
  end

  def load_data(pair, pair_length = 3)
    get_data(pair, pair_length = 3) unless File.exist? "#{pair}_data.csv"
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
        Time.strptime(i + ' utc', '%Y-%m-%d %I-%p %z').to_i*1000
      rescue
        i.to_datetime.to_i*1000
      end
    end
    df = get_today_historical(pair, df.first[:datetime][0] + 1).concat df
    df.sort_by! { |r| r[:datetime] }
  end

  def get_today_historical(pair, startTime = Date.current.to_datetime.to_i*1000)
    url = 'https://api.binance.com/api/v1/klines' +'?symbol=' + pair + '&interval=' + '1h' + '&startTime=' + (startTime).to_s
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
    df[:datetime] = df[:datetime].map { |i| i.to_i }
    [:open, :high, :low, :close, :volume].each { |i| df[i] = df[i].map(&:to_f) }
    df
  end

end