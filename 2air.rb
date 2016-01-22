require 'httpclient'
require 'pry'
require 'json'
require 'faraday'

class FoobotObservation < Struct.new(:uuid, :ts, :all_pollution, :temperature, :humidity, :pm, :co2, :voc)
  # uuid - string
  # ts - timestamp type
  # rest - decimal
end

class FoobotObservationBuilder
  SENSOR_TO_ATTRIBUTE_MAPPING = {
    'allpollu' => :all_pollution,
    'tmp' => :temperature,
    'hum' => :humidity,
    'pm' => :pm,
    'co2' => :co2,
    'voc' => :voc
  }

  def self.create_from_api_json!(sensors, uuid, row)
    observation = FoobotObservation.new

    time_index = sensors.find_index('time')

    observation.uuid = uuid
    observation.ts = Time.at(row[time_index])

    SENSOR_TO_ATTRIBUTE_MAPPING.each do |k,v|
      idx = sensors.find_index(k)
      observation.send("#{v}=", row[idx])
    end

    observation
  end
end

username = 'XXX'
password = 'YYY'
foobot_name = 'ZZZ'
start = (Time.now - 86400).utc.iso8601
finish = Time.now.utc.iso8601


conn = Faraday.new(:url => 'https://api.foobot.io/', :ssl => { :verify =>false}) do |faraday|
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  :httpclient
  faraday.basic_auth username, password
end


res = conn.get("https://api.foobot.io/v2/user/#{username}/login/", ssl: { verify: false })

if res.status != 200
  puts 'Response: ' + res.body
  abort('!!! Foobor authentication failed with status ' + res.status)
end

token = res.headers['x-auth-token']

conn = Faraday.new(:url => 'https://api.foobot.io/', ssl: { verify: false  }) do |faraday|
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
  faraday.headers['x-auth-token'] = token
end

res = conn.get("https://api.foobot.io/v2/owner/#{username}/device/")

if res.status != 200
  puts 'Response: ' + res.body
  abort('!!! Could not fetch devices. Failed with status: ' + res.status)
end

res_json = JSON.parse(res.body)

foobot = res_json.find { |f| f['name'] == foobot_name }

if foobot.nil?
  abort('!!! Could not find Foobot with name ' + foobot_name )
end

foobot_uuid = foobot['uuid']

res = conn.get("https://api.foobot.io/v2/device/#{foobot_uuid}/datapoint/#{start}/#{finish}/0/")

if res.status != 200
  puts 'Response: ' + res.body
  abort('!!! Foobot fetch failed with status ' + res.status.to_s)
end

res_json = JSON.parse(res.body)
puts "RESPONSE"
puts res_json

# Confirm sensors are as expected
expected_sensors = %w(time allpollu tmp hum pm voc co2)

# Find all where they are not included in the response
not_included = expected_sensors.find_all { |s| !res_json['sensors'].include?(s) }
if not_included.length > 0
  abort('!!! Response sensors array doesn\'t include ' + not_included.inspect)
end

# Confirm units are as expected
expected_units = {
    'time' => 's',
    'allpollu' => '%',
    'co2' => 'ppm',
    'tmp' => 'C',
    'hum' => 'pc',
    'pm' => 'ugm3',
    'voc' => 'ppb'
}
expected_units.each do |measure,unit|
  measure_index = res_json['sensors'].find_index measure
  if res_json['units'][measure_index] != unit
    abort("!!! Unit for measure #{measure} does not match expectation of #{unit}. Instead is " +
          "#{res_json['units'][measure_index]}")
  end
end

observations = []
res_json['datapoints'].each do |dp|
  begin
    observations << FoobotObservationBuilder.create_from_api_json!(res_json['sensors'], foobot_uuid, dp)
  end
end

binding.pry
