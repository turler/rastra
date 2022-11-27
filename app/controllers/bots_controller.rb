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
      ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/btcusdt_perpetual@continuousKline_1h'
      # should use Continuous Contract Kline/Candlestick Streams instead?
      stra = Strategies::Advanced.new('BTCUSDT')
      ticker_handler = nil
      ws.on :message do |ticker_msg|
        ws.close unless @bot.reload.running?
        return if ticker_handler.present? && ticker_handler.alive?
        ticker_handler = Thread.new do
          stra.run(ticker_msg.data)
        end
        count += 1
        ws.close if count == 5
      end
      ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/btcusdt_perpetual@continuousKline_1h'
      count = 0
      ticker_handler = nil
      ws.on :message do |ticker_msg|
        ws.close unless @bot.reload.running?
        return if ticker_handler.present? && ticker_handler.alive?
        puts ticker_msg
        ticker_handler = Thread.new do
          sleep 5
        end
        count += 1
        ws.close if count == 5
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
