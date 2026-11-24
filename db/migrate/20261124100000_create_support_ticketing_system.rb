class CreateSupportTicketingSystem < ActiveRecord::Migration[8.1]
  def change
    add_column :feedbacks, :status, :string, default: 'open', null: false unless column_exists?(:feedbacks, :status)
    add_column :feedbacks, :priority, :string, default: 'normal', null: false unless column_exists?(:feedbacks, :priority)
    add_column :feedbacks, :assigned_to_id, :integer, null: true unless column_exists?(:feedbacks, :assigned_to_id)
    add_column :feedbacks, :user_id, :integer, null: true unless column_exists?(:feedbacks, :user_id)
    add_column :feedbacks, :admin_notes, :text, null: true unless column_exists?(:feedbacks, :admin_notes)
    add_column :feedbacks, :last_reply_at, :datetime, null: true unless column_exists?(:feedbacks, :last_reply_at)
    add_column :feedbacks, :last_reply_by, :string, null: true unless column_exists?(:feedbacks, :last_reply_by)

    add_index :feedbacks, :status unless index_exists?(:feedbacks, :status)
    add_index :feedbacks, :user_id unless index_exists?(:feedbacks, :user_id)
    add_index :feedbacks, :assigned_to_id unless index_exists?(:feedbacks, :assigned_to_id)

    unless table_exists?(:feedback_replies)
      create_table :feedback_replies do |t|
        t.integer :feedback_id, null: false
        t.integer :user_id, null: true
        t.integer :admin_id, null: true
        t.string :author_name, null: false
        t.text :comment, null: false
        t.boolean :is_internal, default: false, null: false
        t.timestamps
      end

      add_index :feedback_replies, :feedback_id
      add_index :feedback_replies, :user_id
      add_index :feedback_replies, :admin_id
    end
  end
end
