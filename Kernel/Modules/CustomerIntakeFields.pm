# --
# Kernel/Modules/CustomerIntakeFields.pm - to handle customer messages
# Copyright (C) 2013 Mike McMahon, http://mikemcmahon.github.io
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# -- 

package Kernel::Modules::CustomerIntakeFields;

use strict;
use warnings;

use Kernel::System::State;
use Kernel::System::Web::UploadCache;
use Kernel::System::DynamicField;
use Kernel::System::DynamicField::Backend;
use Kernel::System::VariableCheck qw(:all);
use Kernel::System::MagicForms; 

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (
        qw(ParamObject DBObject TicketObject LayoutObject LogObject QueueObject ConfigObject)
        )
    {
        if ( !$Self->{$Needed} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $Needed!" );
        }
    }
    $Self->{StateObject}        = Kernel::System::State->new(%Param);
    $Self->{UploadCacheObject}  = Kernel::System::Web::UploadCache->new(%Param);
    $Self->{DynamicFieldObject} = Kernel::System::DynamicField->new(%Param);
    $Self->{BackendObject}      = Kernel::System::DynamicField::Backend->new(%Param);

    # Magic Forms
    $Self->{MagicFormsObject}   = Kernel::System::MagicForms->new(%Param);
    if (!$Self->{MagicFormsObject}) { 
        $Self->{LogObject}->Log(
            Priority => 'error', 
            Message => 'Unable to instantiate Magic Forms!');
    }

    # get form id
    $Self->{FormID} = $Self->{ParamObject}->GetParam( Param => 'FormID' );

    # get inform user list
    my @InformUserID = $Self->{ParamObject}->GetArray( Param => 'InformUserID' );
    $Self->{InformUserID} = \@InformUserID;

    # get involved user list
    my @InvolvedUserID = $Self->{ParamObject}->GetArray( Param => 'InvolvedUserID' );
    $Self->{InvolvedUserID} = \@InvolvedUserID;

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Self->{UploadCacheObject}->FormIDCreate();
    }

    # get config of frontend module
    # We'll just pull perms from the stock AgentTicketActionCommon 
    $Self->{Config} = $Self->{ConfigObject}->Get("Ticket::Frontend::$Self->{Action}"); 

    # define the dynamic fields to show based on the object type
    my $ObjectType = ['Ticket'];

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Self->{TicketID} ) {
        return $Self->{LayoutObject}->ErrorScreen(
            Message => 'No TicketID is given!',
            Comment => 'Please contact the admin.',
        );
    }

    $Self->{FormName} = $Self->{ParamObject}->GetParam(Param => 'FormName'); 
    if ( !$Self->{FormName} ) { 
        return $Self->{LayoutObject}->ErrorScreen(
            Message => 'Ticket not associated with a form',
            Comment => 'Please contact the admin if this is in error.',
        );
    }

    $Self->{Display} = $Self->{ParamObject}->GetParam(Param => 'Display') || 'Customer'; 

    if ( !$Self->{Display} ) { 
        return $Self->{LayoutObject}->ErrorScreen(
            Message => 'No Display type specified!',
            Comment => 'Please contact the admin.',
        );
    }

    # get ACL restrictions
    my %Ticket = $Self->{TicketObject}->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 1,
    );

    $Self->{LayoutObject}->Block(
        Name => 'Properties',
        Data => {
            FormID => $Self->{FormID},
            %Ticket,
            %Param,
        },
    );
    # Save the Queue Information
    $Self->{Queue} = $Ticket{Queue};

    if ( $Self->{Display} eq "Customer" ) { 
        $Self->{DynamicField} = $Self->{DynamicFieldObject}->DynamicFieldListGet(
            Valid       => 1,
            ObjectType  => ['Ticket'],
            FieldFilter => $Self->{MagicFormsObject}->DynamicFieldsForCustomer(FormName => $Self->{FormName}) || {},
        );
    } 

    $Self->{LayoutObject}->Block(
        Name => 'TicketBack',
        Data => {
            %Param,
            %Ticket,
        },
    );

    # get params
    my %GetParam;
    for my $Key (
        qw(
        NewStateID NewPriorityID TimeUnits ArticleTypeID Title Body Subject NewQueueID
        Year Month Day Hour Minute NewOwnerID NewOwnerType OldOwnerID NewResponsibleID
        TypeID ServiceID SLAID Expand
        )
        )
    {
        $GetParam{$Key} = $Self->{ParamObject}->GetParam( Param => $Key );
    }

    # get dynamic field values form http request
    my %DynamicFieldValues;

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # extract the dynamic field value form the web request
        $DynamicFieldValues{ $DynamicFieldConfig->{Name} }
            = $Self->{BackendObject}->EditFieldValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ParamObject        => $Self->{ParamObject},
            LayoutObject       => $Self->{LayoutObject},
            );
    }

    # convert dynamic field values into a structure for ACLs
    my %DynamicFieldACLParameters;
    DYNAMICFIELD:
    for my $DynamicField ( sort keys %DynamicFieldValues ) {
        next DYNAMICFIELD if !$DynamicField;
        next DYNAMICFIELD if !$DynamicFieldValues{$DynamicField};

        $DynamicFieldACLParameters{ 'DynamicField_' . $DynamicField }
            = $DynamicFieldValues{$DynamicField};
    }
    $GetParam{DynamicField} = \%DynamicFieldACLParameters;

    # transform pending time, time stamp based on user time zone
    if (
        defined $GetParam{Year}
        && defined $GetParam{Month}
        && defined $GetParam{Day}
        && defined $GetParam{Hour}
        && defined $GetParam{Minute}
        )
    {
        %GetParam = $Self->{LayoutObject}->TransformDateSelection(
            %GetParam,
        );
    }

    # rewrap body if no rich text is used
    if ( $GetParam{Body} && !$Self->{LayoutObject}->{BrowserRichText} ) {
        my $Size = $Self->{ConfigObject}->Get('Ticket::Frontend::TextAreaNote') || 70;
        $GetParam{Body} =~ s/(^>.+|.{4,$Size})(?:\s|\z)/$1\n/gm;
    }

    # fillup configured default vars
    if ( !defined $GetParam{Body} && $Self->{Config}->{Body} ) {
        $GetParam{Body} = $Self->{LayoutObject}->Output(
            Template => $Self->{Config}->{Body},
        );

        # make sure body is rich text
        if ( $Self->{LayoutObject}->{BrowserRichText} ) {
            $GetParam{Body} = $Self->{LayoutObject}->Ascii2RichText(
                String => $GetParam{Body},
            );
        }
    }
    if ( !defined $GetParam{Subject} && $Self->{Config}->{Subject} ) {
        $GetParam{Subject} = $Self->{LayoutObject}->Output(
            Template => $Self->{Config}->{Subject},
        );
    }

    # create html strings for all dynamic fields
    my %DynamicFieldHTML;

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        my $PossibleValuesFilter;

        # check if field has PossibleValues property in its configuration
        if ( IsHashRefWithData( $DynamicFieldConfig->{Config}->{PossibleValues} ) ) {

            # convert possible values key => value to key => key for ACLs usign a Hash slice
            my %AclData = %{ $DynamicFieldConfig->{Config}->{PossibleValues} };
            @AclData{ keys %AclData } = keys %AclData;

            # set possible values filter from ACLs
            my $ACL = $Self->{TicketObject}->TicketAcl(
                %GetParam,
                Action        => $Self->{Action},
                TicketID      => $Self->{TicketID},
                ReturnType    => 'Ticket',
                ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                Data          => \%AclData,
                UserID        => $Self->{UserID},
            );
            if ($ACL) {
                my %Filter = $Self->{TicketObject}->TicketAclData();

                # convert Filer key => key back to key => value using map
                %{$PossibleValuesFilter}
                    = map { $_ => $DynamicFieldConfig->{Config}->{PossibleValues}->{$_} }
                    keys %Filter;
            }
        }

        # to store dynamic field value from database (or undefined)
        my $Value;

        # only get values for Ticket fields (all screens based on AgentTickeActionCommon
        # generates a new article, then article fields will be always empty at the beginign)
        if ( $DynamicFieldConfig->{ObjectType} eq 'Ticket' ) {

            # get value stored on the database from Ticket
            $Value = $Ticket{ 'DynamicField_' . $DynamicFieldConfig->{Name} };
        }

        # get field html
        $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
            $Self->{BackendObject}->DisplayValueRender(
                HTMLOutput => 1,
                DynamicFieldConfig   => $DynamicFieldConfig,
                Value                => $Value,
                LayoutObject    => $Self->{LayoutObject},
                ParamObject     => $Self->{ParamObject},
            );
    }

    # print form ...
    my $Output = $Self->{LayoutObject}->Header(
        Type  => 'Small',
        Value => $Ticket{TicketNumber},
    );
    $Output .= $Self->_Mask(
        %GetParam,
        %Ticket,
        DynamicFieldHTML => \%DynamicFieldHTML,
    );
    $Output .= $Self->{LayoutObject}->Footer(
        Type => 'Small',
    );
    return $Output;
}

sub _Mask {
    my ( $Self, %Param ) = @_;

    # get list type
    my $TreeView = 0;
    if ( $Self->{ConfigObject}->Get('Ticket::Frontend::ListType') eq 'tree' ) {
        $TreeView = 1;
    }
    my %Ticket = $Self->{TicketObject}->TicketGet( TicketID => $Self->{TicketID} );

    if ($Self->{Display}) { 
        $Self->{LayoutObject}->Block(
            Name => 'ScreenType',
            Data => { 
                Display => $Self->{Display},
            }
        );
    }

    my $DynamicFieldNames = $Self->_GetFieldsToUpdate(
        OnlyDynamicFields => 1,
    );

    # create a string with the quoted dynamic field names separated by a commas
    if ( IsArrayRefWithData($DynamicFieldNames) ) {
        my $FirstItem = 1;
        FIELD:
        for my $Field ( @{$DynamicFieldNames} ) {
            if ($FirstItem) {
                $FirstItem = 0;
            }
            else {
                $Param{DynamicFieldNamesStrg} .= ', ';
            }
            $Param{DynamicFieldNamesStrg} .= "'" . $Field . "'";
        }
    }

    # Dynamic fields
    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {

        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # skip fields that HTML could not be retrieved
        next DYNAMICFIELD if !IsHashRefWithData(
            $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} }
        );

        # get the html strings form $Param
        my $DynamicFieldHTML = $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} };

        $Self->{LayoutObject}->Block(
            Name => 'DynamicField',
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Title => $DynamicFieldConfig->{Label},
                Value => $DynamicFieldHTML->{Value},
            },
        );

        # example of dynamic fields order customization
        $Self->{LayoutObject}->Block(
            Name => 'DynamicField_' . $DynamicFieldConfig->{Name},
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldConfig->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );
    }

    # get output back
    return $Self->{LayoutObject}->Output( TemplateFile => $Self->{Action}, Data => \%Param );
}

sub _GetFieldsToUpdate {
    my ( $Self, %Param ) = @_;

    my @UpdatableFields;

    # set the fields that can be updatable via AJAXUpdate
    if ( !$Param{OnlyDynamicFields} ) {
        @UpdatableFields
            = qw(
            TypeID ServiceID SLAID NewOwnerID OldOwnerID NewResponsibleID NewStateID
            NewPriorityID
        );
    }

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        my $Updateable = $Self->{BackendObject}->IsAJAXUpdateable(
            DynamicFieldConfig => $DynamicFieldConfig,
        );

        next DYNAMICFIELD if !$Updateable;

        push @UpdatableFields, 'DynamicField_' . $DynamicFieldConfig->{Name};
    }

    return \@UpdatableFields;
}

1;
