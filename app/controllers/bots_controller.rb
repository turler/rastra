class BotsController < ApplicationController
  before_action :set_bot

  def show
  end

  def start
    if @bot.running?
      flash[:alert] = 'Bot is running'
      return redirect_back fallback_location: bot_path(@bot)
    end
    ProcessService.fork_with_new_connection(@bot.name) do
      @bot.update(running: true)

      ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/bnbusdt@ticker'
      ws.on :message do |msg|
        puts msg
      end
      sleep 5
      ws.close
      @bot.update(running: false)
    end
    redirect_back fallback_location: bot_path(@bot)
  end

  def set_bot
    @bot = Bot.find(params[:id])
  end
end
