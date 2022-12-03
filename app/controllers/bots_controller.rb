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
      # ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/btcusdt@ticker'
      @ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/btcusdt_perpetual@continuousKline_1h'
      # should use Continuous Contract Kline/Candlestick Streams instead?
      @stra = Strategies::Advanced.new('BTCUSDT')
      ticker_handler = nil
      @ws.on :message do |ticker_msg|
        @ws.close if !@bot.reload.running? || @stra.retry_times >= 5
        return if ticker_handler.present? && ticker_handler.alive?
        data = JSON.parse(ticker_msg.data)
        ticker_handler = Thread.new do
          @stra.run(data)
        end
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
