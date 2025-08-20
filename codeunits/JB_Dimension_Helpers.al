codeunit 50105 "JB Dimension Helpers"
{
    procedure ApplyContractAndActPeriodDims(var GenJnlLine: Record "Gen. Journal Line"; ContractCode: Code[20]; ContractName: Text[50]; ActPeriodCode: Code[20]; ActPeriodName: Text[50])
    begin
        if ContractCode <> '' then begin
            EnsureDimensionValue('CONTRACT', ContractCode, ContractName);
            ApplyOneDim(GenJnlLine, 'CONTRACT', ContractCode);
        end;

        if ActPeriodCode <> '' then begin
            EnsureDimensionValue('ACTPERIOD', ActPeriodCode, ActPeriodName);
            ApplyOneDim(GenJnlLine, 'ACTPERIOD', ActPeriodCode);
        end;
    end;

    // Ensure dim value exists (create/update name if available)
    procedure EnsureDimensionValue(DimensionCode: Code[20]; DimValue: Code[20]; NameTxt: Text[50])
    var
        DimVal: Record "Dimension Value";
        Name50: Text[50];
    begin
        if DimValue = '' then
            exit;

        Name50 := NameTxt;

        if not DimVal.Get(DimensionCode, DimValue) then begin
            DimVal.Init();
            DimVal.Validate("Dimension Code", DimensionCode);
            DimVal.Validate(Code, DimValue);
            if Name50 <> '' then
                DimVal.Validate(Name, Name50);
            DimVal.Insert(true);
        end else begin
            if (UpperCase(DelChr(DimVal.Name, '<>', ' ')) = 'AUTOCREATED') and (Name50 <> '') then begin
                DimVal.Name := Name50;
                DimVal.Modify(false);
            end;
        end;
    end;

    // Applies a single dimension to the line:
    // If mapped to a Shortcut Dim (1..8) -> set via both ValidateShortcutDimCode(N, ...) and direct field validate.
    // Otherwise, merge into Dimension Set ID while preserving any existing dimensions on the line.
    local procedure ApplyOneDim(var GenJnlLine: Record "Gen. Journal Line"; DimCode: Code[20]; DimValue: Code[20])
    var
        N: Integer;
        TempExisting: Record "Dimension Set Entry" temporary;
        TempCombined: Record "Dimension Set Entry" temporary;
        DimMgt: Codeunit DimensionManagement;
        NewId: Integer;
    begin
        if DimValue = '' then
            exit;

        N := GetShortcutIndexForDimension(DimCode);
        if N > 0 then begin
            // Primary (updates both shortcut field and dimension set)
            GenJnlLine.ValidateShortcutDimCode(N, DimValue);
            // Defensive: also validate the concrete field to ensure UI columns populate immediately
            SetShortcutFieldByIndex(GenJnlLine, N, DimValue);
            exit;
        end;

        // Not mapped -> merge into Dimension Set ID
        if GenJnlLine."Dimension Set ID" <> 0 then
            DimMgt.GetDimensionSet(TempExisting, GenJnlLine."Dimension Set ID");

        // Build a combined set = existing (minus any same-code entry) + our new entry
        if TempExisting.FindSet() then
            repeat
                if UpperCase(TempExisting."Dimension Code") <> UpperCase(DimCode) then begin
                    TempCombined.Init();
                    TempCombined.TransferFields(TempExisting);
                    TempCombined.Insert();
                end;
            until TempExisting.Next() = 0;

        TempCombined.Init();
        TempCombined.Validate("Dimension Code", DimCode);
        TempCombined.Validate("Dimension Value Code", DimValue);
        TempCombined.Insert();

        NewId := DimMgt.GetDimensionSetID(TempCombined);
        GenJnlLine."Dimension Set ID" := NewId;
    end;

    // Returns 1..8 if the provided Dimension Code is mapped to a Shortcut Dimension N in General Ledger Setup
    local procedure GetShortcutIndexForDimension(DimCode: Code[20]): Integer
    var
        GLSetup: Record "General Ledger Setup";
        i: Integer;
        CodeTxt: Code[20];
    begin
        if not GLSetup.Get() then
            exit(0);

        for i := 1 to 8 do begin
            CodeTxt := GetShortcutDimCode(GLSetup, i);
            if (CodeTxt <> '') and (UpperCase(CodeTxt) = UpperCase(DimCode)) then
                exit(i);
        end;

        exit(0);
    end;

    local procedure GetShortcutDimCode(GLSetup: Record "General Ledger Setup"; Index: Integer): Code[20]
    begin
        case Index of
            1:
                exit(GLSetup."Shortcut Dimension 1 Code");
            2:
                exit(GLSetup."Shortcut Dimension 2 Code");
            3:
                exit(GLSetup."Shortcut Dimension 3 Code");
            4:
                exit(GLSetup."Shortcut Dimension 4 Code");
            5:
                exit(GLSetup."Shortcut Dimension 5 Code");
            6:
                exit(GLSetup."Shortcut Dimension 6 Code");
            7:
                exit(GLSetup."Shortcut Dimension 7 Code");
            8:
                exit(GLSetup."Shortcut Dimension 8 Code");
        end;
        exit('');
    end;

    // Explicitly validate the shortcut field to ensure the visible column is populated
    local procedure SetShortcutFieldByIndex(var GenJnlLine: Record "Gen. Journal Line"; Index: Integer; Value: Code[20])
    begin
        case Index of
            1:
                GenJnlLine.Validate("Shortcut Dimension 1 Code", Value);
            2:
                GenJnlLine.Validate("Shortcut Dimension 2 Code", Value);
            3:
                GenJnlLine.Validate("Shortcut Dimension 3 Code", Value);
            4:
                GenJnlLine.Validate("Shortcut Dimension 4 Code", Value);
            5:
                GenJnlLine.Validate("Shortcut Dimension 5 Code", Value);
            6:
                GenJnlLine.Validate("Shortcut Dimension 6 Code", Value);
            7:
                GenJnlLine.Validate("Shortcut Dimension 7 Code", Value);
            8:
                GenJnlLine.Validate("Shortcut Dimension 8 Code", Value);
        end;
    end;
}