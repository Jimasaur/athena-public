namespace :athena do
  desc "Create missing work items for existing idea cards without overwriting operator edits"
  task backfill_work_items: :environment do
    created = 0
    IdeaCapture.find_each do |idea|
      next if WorkItem.exists?(idea_capture_id: idea.id)

      WorkItemFromIdeaService.new(idea_capture: idea, actor: "idea backfill").call
      created += 1
    end
    puts "Created #{created} work items. Existing work items were preserved."
  end
end
