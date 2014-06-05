# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-669

require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), 'example_app')
require 'new_relic/rack/browser_monitoring'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/error_collector'

class RackAutoInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

  def self.app
    @app ||= Rack::Builder.app do
      use MiddlewareOne
      use MiddlewareTwo
      use NewRelic::Rack::BrowserMonitoring
      use NewRelic::Rack::AgentHooks
      use NewRelic::Rack::ErrorCollector
      run ExampleApp.new
    end
  end

  # Each test executes in a unique instance of RackAutoInstrumentationTest
  # We only want to build ExampleApp once so we need to use a class method.
  def app
    self.class.app
  end

  def test_middleware_gets_used
    get '/'
    assert last_response.headers['MiddlewareOne']
    assert last_response.headers['MiddlewareTwo']
  end

  def test_status_code_is_preserved
    get '/'
    assert_equal 200, last_response.status
  end

  def test_header_is_preserved
    get '/'
    assert last_response.headers['ExampleApp']
  end

  def test_body_is_preserved
    get '/'
    assert_equal 'A barebones rack app.', last_response.body
  end

  def test_middlewares_record_metrics
    NewRelic::Agent.drop_buffered_data
    get '/'
    assert_metrics_recorded_exclusive(
      [
        "Apdex",
        "HttpDispatcher",
        "Middleware/all",
        "Apdex/Rack/ExampleApp/call",
        "Controller/Rack/ExampleApp/call",
        "Middleware/Rack/MiddlewareOne/call",
        "Middleware/Rack/MiddlewareTwo/call",
        "Middleware/Rack/NewRelic::Rack::ErrorCollector/call",
        "Middleware/Rack/NewRelic::Rack::BrowserMonitoring/call",
        "Middleware/Rack/NewRelic::Rack::AgentHooks/call",
        "Nested/Controller/Rack/ExampleApp/call",
        ["Middleware/Rack/NewRelic::Rack::ErrorCollector/call",    "Controller/Rack/ExampleApp/call"],
        ["Middleware/Rack/NewRelic::Rack::BrowserMonitoring/call", "Controller/Rack/ExampleApp/call"],
        ["Middleware/Rack/NewRelic::Rack::AgentHooks/call",        "Controller/Rack/ExampleApp/call"],
        ["Middleware/Rack/MiddlewareOne/call", "Controller/Rack/ExampleApp/call"],
        ["Middleware/Rack/MiddlewareTwo/call", "Controller/Rack/ExampleApp/call"],
        ["Nested/Controller/Rack/ExampleApp/call",    "Controller/Rack/ExampleApp/call"]
      ],
      :ignore_filter => /^Supportability\/EnvironmentReport/
    )
  end

  def test_middlewares_record_queue_time
    t0 = freeze_time
    advance_time(5.0)
    get '/', {}, { 'HTTP_X_REQUEST_START' => "t=#{t0.to_f}" }

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => { :total_call_time => 5.0 }
    )
  end

  def test_middleware_that_returns_early_records_middleware_rollup_metric
    get '/?return-early=true'
    assert_metrics_recorded_exclusive([
      "Apdex",
      "HttpDispatcher",
      "Middleware/all",
      "Apdex/Middleware/Rack/MiddlewareTwo/call",
      "Controller/Middleware/Rack/MiddlewareTwo/call",
      "Middleware/Rack/MiddlewareOne/call",
      "Middleware/Rack/MiddlewareTwo/call",
      ["Middleware/Rack/MiddlewareOne/call", "Controller/Middleware/Rack/MiddlewareTwo/call"],
      ["Middleware/Rack/MiddlewareTwo/call", "Controller/Middleware/Rack/MiddlewareTwo/call"]
    ])
  end

  def test_middleware_that_returns_early_middleware_all_has_correct_call_times
    t0 = freeze_time

    get '/?return-early=true'
    assert_metrics_recorded('Middleware/all' => { :total_exclusive_time => 3.0, :call_count => 2 })
  end
end