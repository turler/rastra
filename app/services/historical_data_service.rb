class HistoricalDataService
  def get_data(pair, pair_length = 3)
    File.write "#{pair}.csv", HTTPX.get("https://www.cryptodatadownload.com/cdd/Binance_#{pair}_1h.csv").read
    file = File.open "#{pair}.csv"
    file.gets # read the first line, but ignore it since it contains non-CSV data
    File.write "#{pair}_data.csv", file.read
    file.close
    File.delete "#{pair}.csv"
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
    df
  end
end