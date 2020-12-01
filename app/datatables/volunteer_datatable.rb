class VolunteerDatatable < ApplicationDatatable
  ORDERABLE_FIELDS = %w[
    active
    contacts_made_in_past_days
    display_name
    email
    has_transition_aged_youth_cases
    most_recent_contact_occurred_at
    supervisor_name
  ]

  private

  def data
    records.map(&:decorate).map do |volunteer|
      {
        active: volunteer.active,
        casa_cases: volunteer.casa_cases.map { |cc| {id: cc.id, case_number: cc.case_number} },
        contacts_made_in_past_days: volunteer.contacts_made_in_past_days,
        display_name: volunteer.display_name,
        email: volunteer.email,
        has_transition_aged_youth_cases: volunteer.has_transition_aged_youth_cases?,
        id: volunteer.id,
        made_contact_with_all_cases_in_days: volunteer.made_contact_with_all_cases_in_days?,
        most_recent_contact: {case_id: volunteer.most_recent_contact_case_id, occurred_at: volunteer.most_recent_contact_occurred_at.try(:strftime, "%B %-e, %Y")},
        supervisor: {id: volunteer.supervisor_id, name: volunteer.supervisor_name}
      }
    end
  end

  def filtered_records
    raw_records
      .where(supervisor_filter)
      .where(active_filter)
      .where(transition_aged_youth_filter)
      .where(search_filter)
  end

  def raw_records
    base_relation
      .select(
        <<-SQL
          users.*,
          COALESCE(supervisors.display_name, supervisors.email) AS supervisor_name,
          supervisors.id AS supervisor_id,
          transition_aged_youth_cases.volunteer_id IS NOT NULL AS has_transition_aged_youth_cases,
          most_recent_contacts.casa_case_id AS most_recent_contact_case_id,
          most_recent_contacts.occurred_at AS most_recent_contact_occurred_at,
          contacts_made_in_past_days.contact_count AS contacts_made_in_past_days
        SQL
      )
      .joins(
        <<-SQL
          LEFT JOIN supervisor_volunteers ON supervisor_volunteers.volunteer_id = users.id AND supervisor_volunteers.is_active
          LEFT JOIN users supervisors ON supervisors.id = supervisor_volunteers.supervisor_id AND supervisors.active
          LEFT JOIN (
            #{transition_aged_youth_cases_subquery}
          ) transition_aged_youth_cases ON transition_aged_youth_cases.volunteer_id = users.id
          LEFT JOIN (
            #{most_recent_contacts_subquery}
          ) most_recent_contacts ON most_recent_contacts.creator_id = users.id AND most_recent_contacts.contact_index = 1
          LEFT JOIN (
            #{contacts_made_in_past_days_subquery}
          ) contacts_made_in_past_days ON contacts_made_in_past_days.creator_id = users.id
        SQL
      )
      .order(order_clause)
      .order(:id)
      .includes(:casa_cases)
  end

  def transition_aged_youth_cases_subquery
    @transition_aged_youth_cases_subquery ||=
      CaseAssignment
        .select(:volunteer_id)
        .joins(:casa_case)
        .where(casa_cases: {transition_aged_youth: true})
        .group(:volunteer_id)
        .to_sql
  end

  def most_recent_contacts_subquery
    @most_recent_contacts_subquery ||=
      CaseContact
        .select(
          <<-SQL
          *,
          ROW_NUMBER() OVER(PARTITION BY creator_id ORDER BY occurred_at DESC NULLS LAST) AS contact_index
          SQL
        )
        .where(contact_made: true)
        .to_sql
  end

  def contacts_made_in_past_days_subquery
    @contacts_made_in_past_days_subquery ||=
      CaseContact
        .select(
          <<-SQL
          creator_id,
          COUNT(*) AS contact_count
          SQL
        )
        .where(contact_made: true, occurred_at: Volunteer::CONTACT_MADE_IN_PAST_DAYS_NUM.days.ago.to_date..)
        .group(:creator_id)
        .to_sql
  end

  def order_clause
    @order_clause ||= build_order_clause || Arel.sql("COALESCE(users.display_name, users.email) ASC")
  end

  def supervisor_filter
    @supervisor_filter ||=
      if (filter = additional_filters[:supervisor]).blank?
        "FALSE"
      elsif filter.all?(&:blank?)
        "supervisors.id IS NULL"
      else
        null_filter = "supervisors.id IS NULL OR" if filter.any?(&:blank?)
        ["#{null_filter} COALESCE(supervisors.display_name, supervisors.email) IN (?)", filter.select(&:present?)]
      end
  end

  def active_filter
    @active_filter ||=
      lambda {
        filter = additional_filters[:active]

        bool_filter filter do
          ["users.active = ?", filter[0]]
        end
      }.call
  end

  def transition_aged_youth_filter
    @transition_aged_youth_filter ||=
      lambda {
        filter = additional_filters[:transition_aged_youth]

        bool_filter filter do
          "transition_aged_youth_cases.volunteer_id IS #{filter[0] == "true" ? "NOT" : nil} NULL"
        end
      }.call
  end

  def search_filter
    @search_filter ||=
      lambda {
        return "TRUE" if search_term.blank?

        clause_string =
          "users.display_name ILIKE ?" \
          " OR users.email ILIKE ?" \
          " OR supervisors.display_name ILIKE ?" \
          " OR supervisors.email ILIKE ?" \
          " OR users.id IN (#{casa_case_number_filter_subquery})"

        [clause_string, 4.times.map { "%#{search_term}%" }].flatten
      }.call
  end

  def casa_case_number_filter_subquery
    @casa_case_number_filter_subquery ||=
      lambda {
        return "" if search_term.blank?

        CaseAssignment
          .select(:volunteer_id)
          .joins(:casa_case)
          .where("casa_cases.case_number ILIKE ?", "%#{search_term}%")
          .group(:volunteer_id)
          .to_sql
      }.call
  end
end
