codeunit 50116 "JB Posting Helper"
{
    procedure PostBatch(TemplateName: Code[10]; BatchName: Code[10]): Boolean
    var
        GenJnlLine: Record "Gen. Journal Line";
        TempGenJnlLine: Record "Gen. Journal Line" temporary;
        GenJnlLineUpd: Record "Gen. Journal Line";
        NoSeries: Codeunit "No. Series";
        GenJnlPost: Codeunit "Gen. Jnl.-Post";
        PrevDoc: Code[20];
        DraftDoc: Code[20];
        PostedNo: Code[20];
        UsageDate: Date;
    begin
        // Build a temp list of the batch's Document Nos (sorted) so we can iterate distinct draft ids
        GenJnlLine.Reset();
        GenJnlLine.SetRange("Journal Template Name", TemplateName);
        GenJnlLine.SetRange("Journal Batch Name", BatchName);
        GenJnlLine.SetCurrentKey("Document No.");
        if not GenJnlLine.FindSet() then
            exit(false);

        repeat
            // Skip blank document nos (shouldn't normally happen after builder change)
            if GenJnlLine."Document No." <> '' then begin
                TempGenJnlLine := GenJnlLine;
                TempGenJnlLine.Insert();
            end;
        until GenJnlLine.Next() = 0;

        // Iterate temp record in Document No order and for each distinct draft, reserve a posted number and update real lines
        PrevDoc := '';
        TempGenJnlLine.Reset();
        TempGenJnlLine.SetCurrentKey("Document No.");
        if TempGenJnlLine.FindSet() then
            repeat
                DraftDoc := TempGenJnlLine."Document No.";
                if DraftDoc <> PrevDoc then begin
                    PrevDoc := DraftDoc;
                    // Reserve next posted number from SALPOST
                    UsageDate := WorkDate();
                    PostedNo := NoSeries.GetNextNo('SALPOST', UsageDate);

                    // Update all real lines with this draft doc to the new posted number
                    GenJnlLineUpd.Reset();
                    GenJnlLineUpd.SetRange("Journal Template Name", TemplateName);
                    GenJnlLineUpd.SetRange("Journal Batch Name", BatchName);
                    GenJnlLineUpd.SetRange("Document No.", DraftDoc);
                    if GenJnlLineUpd.FindSet() then
                        repeat
                            GenJnlLineUpd.Validate("Document No.", PostedNo);
                            GenJnlLineUpd.Modify(true);
                        until GenJnlLineUpd.Next() = 0;
                end;
            until TempGenJnlLine.Next() = 0;

        // Persist the Document No updates before posting
        Commit();

        // Now call the standard posting codeunit (no return value used)
        Clear(GenJnlLine);
        GenJnlLine.Reset();
        GenJnlLine.SetRange("Journal Template Name", TemplateName);
        GenJnlLine.SetRange("Journal Batch Name", BatchName);
        if not GenJnlLine.FindSet() then
            exit(false);

        // Run posting (no return value)
        GenJnlPost.Run(GenJnlLine);

        // Verify there are no remaining lines in the batch
        GenJnlLine.Reset();
        GenJnlLine.SetRange("Journal Template Name", TemplateName);
        GenJnlLine.SetRange("Journal Batch Name", BatchName);
        exit(not GenJnlLine.FindFirst());
    end;
}
