require "rails_helper"

RSpec.describe SupervisorImporter do
  let!(:import_user) { build(:casa_admin) }
  let(:casa_org_id) { import_user.casa_org.id }

  # Use of the static method SupervisorImporter.import_volunteers functions identically to SupervisorImporter.new(...).import_volunteers
  # but is preferred.
  let(:supervisor_import_data_path) { Rails.root.join("spec", "fixtures", "supervisors.csv") }

  let(:supervisor_importer) do
    importer = SupervisorImporter.new(supervisor_import_data_path, casa_org_id)

    allow(importer).to receive(:email_addresses_to_users) do |_clazz, supervisor_volunteers|
      create_list(:volunteer, supervisor_volunteers.split(",").size, casa_org: import_user.casa_org)
    end

    importer
  end

  it "imports supervisors and associates volunteers with them" do
    expect { supervisor_importer.import_supervisors }.to change(Supervisor, :count).by(3)
    expect(Supervisor.find_by(email: "supervisor1@example.net").volunteers.size).to eq(1)
    expect(Supervisor.find_by(email: "supervisor2@example.net").volunteers.size).to eq(2)
    expect(Supervisor.find_by(email: "supervisor3@example.net").volunteers.size).to eq(0)
  end

  it "returns a success message with the number of supervisors imported" do
    alert = supervisor_importer.import_supervisors
    expect(alert[:type]).to eq(:success)
    expect(alert[:message]).to eq("You successfully imported 3 supervisors.")
  end

  context "when the supervisors have already been imported" do
    before { supervisor_importer.import_supervisors }

    it "does not import duplicate supervisors from csv files" do
      expect { supervisor_importer.import_supervisors }.to change(Supervisor, :count).by(0)
    end

    it "returns an error message when there are volunteers not imported" do
      alert = SupervisorImporter.new(supervisor_import_data_path, import_user.casa_org.id).import_supervisors
      expect(alert[:type]).to eq(:error)
      expect(alert[:message]).to include("Not all rows were imported.")
    end

    it "returns an error message when there are only some volunteers not imported" do
      create(:volunteer, email: "volunteer1@example.net")
      import_supervisor_path = Rails.root.join("spec", "fixtures", "supervisor_volunteers.csv")
      alert = SupervisorImporter.new(import_supervisor_path, import_user.casa_org.id).import_supervisors

      expect(alert[:type]).to eq(:error)
    end
  end

  context "when updating supervisors" do
    let!(:existing_supervisor) { create(:supervisor, display_name: "#", email: "supervisor2@example.net") }

    it "assignes unassigned volunteers" do
      expect {
        supervisor_importer.import_supervisors
      }.to change(existing_supervisor.volunteers, :count).by(2)
    end

    it "updates outdated supervisor fields" do
      expect {
        supervisor_importer.import_supervisors
        existing_supervisor.reload
      }.to change(existing_supervisor, :display_name).to("Supervisor Two")
    end
  end

  context "when row doesn't have e-mail address" do
    let(:supervisor_import_data_path) { Rails.root.join("spec", "fixtures", "supervisors_without_email.csv") }

    it "returns an error message" do
      alert = supervisor_importer.import_supervisors

      expect(alert[:type]).to eq(:error)
      expect(alert[:message]).to eq("You successfully imported 1 supervisors. Not all rows were imported.")
      expect(alert[:exported_rows]).to include("Row does not contain e-mail address.")
    end
  end

  specify "static and instance methods have identical results" do
    SupervisorImporter.new(supervisor_import_data_path, casa_org_id).import_supervisors
    data_using_instance = Supervisor.pluck(:email).sort

    Supervisor.delete_all
    SupervisorImporter.import_supervisors(supervisor_import_data_path, casa_org_id)
    data_using_static = Supervisor.pluck(:email).sort

    expect(data_using_static).to eq(data_using_instance)
    expect(data_using_static).to_not be_empty
  end
end
