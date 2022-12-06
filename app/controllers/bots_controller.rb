class BotsController < ApplicationController
  before_action :set_bot

  def show
  end

  def start
    if @bot.running?
      flash[:alert] = 'Bot is running'
      return redirect_back fallback_location: bot_path(@bot)
    end
    @bot.update(running: true)
    ProcessService.fork_with_new_connection(@bot.name) do
      @stra = Strategies::Advanced.new('BTCUSDT')
      ticker_handler = nil
      loop do
        break if !Bot.find(@bot.id).running? || @stra.retry_times >= 5
        url = 'https://fapi.binance.com/fapi/v1/continuousKlines' +'?pair=' + 'BTCUSDT' + '&contractType=' + 'PERPETUAL' + '&interval=' + '1h' + '&startTime=' + (Time.current.beginning_of_hour.to_i*1000).to_s
        page = HTTPX.get(url)
        data = page.json.first
        handle_data = [{
          datetime: data[0],
          open: data[1].to_f,
          high: data[2].to_f,
          low: data[3].to_f,
          close: data[4].to_f,
          volume: data[5].to_f,
        }]
        @stra.run(handle_data)
        sleep(0.5)
      end
    end
    redirect_back fallback_location: bot_path(@bot)
  end

  def stop
    @bot.update(running: false)
    redirect_back fallback_location: bot_path(@bot)
  end

  def set_bot
    @bot = Bot.find(params[:id])
  end
end
