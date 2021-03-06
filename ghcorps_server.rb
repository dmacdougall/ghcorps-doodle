require "oauth"
require "nokogiri"
require "thin"
require "digest/sha1"
require "./models/user"
require "./models/poll"

class GHCorps < Sinatra::Base
  enable :sessions

  configure do
    set :tokens, Hash.new { |hash, key| hash[key] = {} }
  end

  configure :development do
    GHCORPS_HOST = "http://127.0.0.1:8000"
  end

  configure :production do
    GHCORPS_HOST = "http://ghcorps.herokuapp.com"
  end

  COUNTRIES = {
    "B" => { :code => "B", :name => "Burundi" },
    "M" => { :code => "M", :name => "Malawi" },
    "R" => { :code => "R", :name => "Rwanda" },
    "UG" => { :code => "UG", :name => "Uganda" },
    "Z" => { :code => "Z", :name => "Zambia" },
    "US-A" => { :code => "US-A", :name => "USA-American" },
    "US-I" => { :code => "US-I", :name => "USA-International" },
    "T" => { :code => "T", :name => "Test" }
  }

  before do
    authorize! unless access_token || request.path.include?("oauth")
  end

  get "/" do
    user = User.get_user(access_token)
    erb :index, :locals => { :polls => user.polls, :countries => COUNTRIES.values }
  end

  get "/country_data/:country_code" do
    user = User.get_user(access_token)
    poll_info = user.polls.select do |poll|
      poll[:title].start_with?("#{params[:country_code][0..1].upcase}-") &&
          (poll[:title].include?("American") || poll[:title].include?("International"))
    end

    # Filter US American or US International
    if params[:country_code].start_with?("US")
      poll_info = params[:country_code].end_with?("A") ?
          poll_info.select { |info| info[:title].include?("American") } :
          poll_info.select { |info| info[:title].include?("International") }
    end

    polls = poll_info.map { |poll| poll[:id] }.map do |poll_id|
      Poll.get_poll(access_token, poll_id)
    end

    participants = polls.map(&:participants).inject(&:concat).sort do |a, b|
      first = a[:poll_code] <=> b[:poll_code]
      first.zero? ? a[:name] <=> b[:name] : first
    end

    content_type "text/csv"
    headers "Content-Disposition" => "attachment;filename=#{COUNTRIES[params[:country_code]][:name]}.csv"
    erb :country_data, :locals => { :participants => participants }, :layout => false
  end

  get "/oauth/callback" do
    make_access_token!(params[:oauth_verifier])
    redirect "/"
  end

  def authorize!
    redirect request_token.authorize_url unless access_token
  end

  def consumer
    settings.tokens[session_id][:consumer] ||= OAuth::Consumer.new("nur1oamwpszmvkaal7fmrh2vnlqkj8pw", "24nfmsyeh8shl7mo1z5iku7vj5uzqn2b",
      { :site => "http://doodle.com", :request_token_path => "/api1/oauth/requesttoken",
        :access_token_path => "/api1/oauth/accesstoken", :authorize_path => "/api1/oauth/authorizeConsumer" })
  end

  def request_token
    settings.tokens[session_id][:request_token] ||= consumer.get_request_token(
        { :oauth_callback => "#{GHCORPS_HOST}/oauth/callback" },
        { "doodle_get" => "name|initiatedPolls"} )
  end

  def make_access_token!(oauth_verifier)
    settings.tokens[session_id][:access_token] ||= request_token.get_access_token(:oauth_verifier => oauth_verifier)
  end

  def access_token() settings.tokens[session_id][:access_token] end

  def session_id() session[:id] ||= unique_id! end
  def unique_id!() Digest::SHA1.hexdigest(Time.now.to_s) end
end
