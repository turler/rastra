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
      ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/btcusdt@ticker'
      # should use Continuous Contract Kline/Candlestick Streams instead?
      stra = Strategies::Advanced.new('BTCUSDT')
      ws.on :message do |ticker_msg|
        ws.close unless @bot.reload.running?
        stra.run(ticker_msg.data)
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
