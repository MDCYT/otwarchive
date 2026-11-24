class AddTicketTypeAndReportedUrlToFeedbacks < ActiveRecord::Migration[8.1]
  def change
    add_column :feedbacks, :ticket_type, :string, default: 'technical', null: false unless column_exists?(:feedbacks, :ticket_type)
    add_column :feedbacks, :reported_url, :string, limit: 2080, null: true unless column_exists?(:feedbacks, :reported_url)
    add_index :feedbacks, :ticket_type unless index_exists?(:feedbacks, :ticket_type)
  end
end

