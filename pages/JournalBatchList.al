page 50117 "Journal Batch List"
{
    PageType = List;
    SourceTable = "Gen. Journal Batch";
    ApplicationArea = All;
    UsageCategory = Lists;  // Changed from Administration to Lists for better visibility
    Caption = 'Salary Import - Journal Batches';  // More descriptive caption

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("Journal Template Name"; Rec."Journal Template Name") { ApplicationArea = All; }
                field(Name; Rec.Name) { ApplicationArea = All; }
                field("Description"; Rec.Description) { ApplicationArea = All; }
                field("No. Series"; Rec."No. Series") { ApplicationArea = All; }
                field("Posting No. Series"; Rec."Posting No. Series") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PostBatch)
            {
                ApplicationArea = All;
                Caption = 'Post Batch (Salary Import)';
                Image = PostBatch;
                ToolTip = 'Reserve posted numbers from SALPOST and post the selected journal batch via Salary Import helper.';

                trigger OnAction()
                var
                    PostingHelper: Codeunit "JB Posting Helper";
                begin
                    if not Confirm('Post journal batch %1/%2 using Salary Import posting helper?', false, Rec."Journal Template Name", Rec.Name) then
                        exit;

                    Commit();
                    ClearLastError();

                    if PostingHelper.PostBatch(Rec."Journal Template Name", Rec.Name) then
                        Message('Batch %1/%2 posted successfully.', Rec."Journal Template Name", Rec.Name)
                    else
                        Error('Posting failed: %1', GetLastErrorText());
                end;
            }
        }
    }
}
