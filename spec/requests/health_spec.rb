require "rails_helper"

RSpec.describe "Health", type: :request do
  before do
    Casa::Application.load_tasks
    Rake::Task["after_party:store_deploy_time"].invoke
  end

  describe "GET /health" do
    before do
      get "/health"
    end

    it "renders an html file" do
      # delete this test when there are more specific tests about the page
      expect(response.header["Content-Type"]).to include("text/html")
    end
  end

  describe "GET /health.json" do
    before do
      get "/health.json"
    end

    it "renders a json file" do
      expect(response.header["Content-Type"]).to include("application/json")
    end

    it "has key latest_deploy_time" do
      hash_body = nil # This is here for the linter
      expect { hash_body = JSON.parse(response.body).with_indifferent_access }.not_to raise_exception
      expect(hash_body.keys).to match_array(["latest_deploy_time"])
    end
  end

  describe "GET #case_contacts_creation_times_in_last_week" do
    it "returns timestamps of case contacts created in the last week" do
      case_contact1 = create(:case_contact, created_at: 1.week.ago)
      case_contact2 = create(:case_contact, created_at: 2.weeks.ago)
      get case_contacts_creation_times_in_last_week_health_index_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      timestamps = JSON.parse(response.body)["timestamps"]
      expect(timestamps).to include(case_contact1.created_at.to_i)
      expect(timestamps).not_to include(case_contact2.created_at.iso8601(3))
    end
  end

  describe "GET #case_contacts_creation_times_in_last_year" do
    it "returns case contacts creation times in the last year" do
      # Create case contacts for testing
      create(:case_contact, notes: "Test Notes", created_at: 11.months.ago)
      create(:case_contact, notes: "", created_at: 11.months.ago)
      create(:case_contact, created_at: 10.months.ago)
      create(:case_contact, created_at: 9.months.ago)

      get case_contacts_creation_times_in_last_year_health_index_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")

      chart_data = JSON.parse(response.body)
      expect(chart_data).to be_an(Array)
      expect(chart_data.length).to eq(12)

      expect(chart_data[0]).to eq([11.months.ago.strftime("%b %Y"), 2, 1, 2])
      expect(chart_data[1]).to eq([10.months.ago.strftime("%b %Y"), 1, 0, 1])
      expect(chart_data[2]).to eq([9.months.ago.strftime("%b %Y"), 1, 0, 1])
      expect(chart_data[3]).to eq([8.months.ago.strftime("%b %Y"), 0, 0, 0])
    end
  end
end
