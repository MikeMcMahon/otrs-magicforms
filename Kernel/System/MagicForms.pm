# --
# Kernel/System/MagicForms.pm - to handle customer messages
# Copyright (C) 2013 Mike McMahon, http://mikemcmahon.github.io
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
package Kernel::System::MagicForms;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.0.4 $) [1]; 

sub new { 
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{Debug} = 0; 

    # check needed Objects
    for (qw( ParamObject LayoutObject LogObject ConfigObject ))
    {
        if ( !$Self->{$_} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $_!" );
        }
    }

    $Self->{DynamicFieldObject} = Kernel::System::DynamicField->new(%Param);

    return $Self;
}

sub _GetDynamicFields { 
    my  ( $Self, %Param ) = @_;

    # check for needed stuff... 
    for ( qw ( Screen ) ) { 
        if ( !$Param{$_} ) { 
            $Self->{LogObject}->Log(Priority => 'error',Message => "Need $_!");
            return;
        }
    }

    if ( !$Param{FormName} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "No form name specified, returning default field",
        ); 

        # Return the default field
        return $Self->_DefaultDynamicField();
    }
   
    my $FormName = $Param{FormName};
    my $FormsToDynamicFields = $Self->{ConfigObject}->Get("MagicForms::$Param{Screen}::DynamicFieldToForm") || {}; 

    if (!%$FormsToDynamicFields) { 
        $Self->{LogObject}->Log(Priority => 'notice', Message => 'No Form to DynamicFields found!');
    }

    my $DynamicFields = {};
    my @DynamicField = (); 

    while ( my ($key, $value) = each %$FormsToDynamicFields ) { 
        if ($FormName eq $key) {
            # Get the sub hash (if it is a sub hash)
            if (ref($value) eq "HASH") {
                while ( my ($field, $req) = each %$value) { 
                    $DynamicFields->{ $field } = $req; 
                    if ( $Self->{Debug} > 0 ) { 
                        $Self->{LogObject}->Log(
                            Priority => 'notice', 
                            Message => "Adding $field with value of $req to dynamic fields array",
                        );
                    }
                }
            }
        }
    }

    return $DynamicFields;
}

sub _GetDynamicField { 
    my ( $Self, %Param ) = @_; 

    # check for needed stuff...
    for ( qw ( FormName DynamicField Screen ) ) { 
        if ( !$Param{$_} ) { 
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "Missing $_!");
            return;
        }
    }
    # Get all of the dynamic fields for a given queue
    my $DynamicFields = $Self->_GetDynamicFields(FormName => $Param{FormName}, Screen => $Param{Screen}); 
    while (my ($Key, $Value) = each(%$DynamicFields)) { 
       if ( $Key eq $Param{DynamicField} ) {
           # Return the matched field
           return { $Key => $Value }; 
       }
    }

    # Otherwise return an empty hash 
    return {}; 
}

sub DynamicFieldsForAgent { 
    my ( $Self, %Param ) = @_; 

    return $Self->_GetDynamicFields(FormName => $Param{FormName}, Screen => 'Agent') || {}; 
}

sub DynamicFieldsForCustomer { 
    my ( $Self, %Param ) = @_; 

    return $Self->_GetDynamicFields(FormName => $Param{FormName}, Screen => 'Customer') || {}; 
}

sub DynamicFieldsForBoth { 
    my ( $Self, %Param ) = @_; 

    for ( qw ( FormName ) ) { 
        if ( !$Param{$_} ) { 
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "Missing $_!"); 
            return;
        }
    }

    my ( $AgentDynamicFields, $CustomerDynamicFields ); 
    $AgentDynamicFields = $Self->DynamicFieldsForAgent(FormName => $Param{FormName}); 
    $CustomerDynamicFields = $Self->DynamicFieldsForCustomer(FormName => $Param{FormName}); 

    while ( my ($Key, $Val) = each(%$CustomerDynamicFields) ) {
        if ( $Self->{Debug} > 0 ) { 
            $Self->{LogObject}->Log(Priority=>'notice',Message=>"$Key => $Val");
        }
        $AgentDynamicFields->{$Key} = $Val; 
    }

    # Combine the values with a simple hash slice
    return $AgentDynamicFields;
}

sub _DefaultDynamicField { 
    my ( $Self, %Param ) = @_; 

    # When no form is specified this is the default field we return
    return { $Self->{ConfigObject}->Get('MagicForms::DynamicField') || MagicForms  => 2 }; 
}

sub IsRequiredForForm {
    my ( $Self, %Param ) = @_; 

    # check for needed stuff...
    for ( qw ( DynamicField Default ) ) { 
        if ( !$Param{$_} ) { 
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "Missing $_!");
            return 0;
        }
    }
    
    if ( !$Param{FormName} && $Param{DynamicField} eq ( $Self->{ConfigObject}->Get('MagicForms::DynamicField') || 'MagicForms' ) ) { 

        # ALWAYS REQUIRE THE DEFAULT FIELD
        return 2; 
    }

    my $DynamicField = $Self->_GetDynamicField(
        FormName => $Param{FormName}, 
        DynamicField => $Param{DynamicField}, 
        Screen => $Param{Screen} || 'Customer', #Optional Param, valid values =  Screen or Agent
    ); 
    
    # if the hash contains the dynamic field... 
    if ( exists $DynamicField->{$Param{DynamicField}} ) {
        return $DynamicField->{$Param{DynamicField}};
    }

    # if no dynamic field is found, return the default value passed in for this DF
    return $Param{Default};
}

sub IsRequiredForAny { 
    my ( $Self, %Param ) = @_; 
    # Check for needed stuff
    for ( qw ( DynamicField ) ) { 
        if ( !$Param{$_} ) { 
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "Missing $_!");
            return 0;
        }
    }

    my $Required = $Self->IsRequiredForForm(
        FormName => $Param{FormName},
        DynamicField => $Param{DynamicField},
        Default => -1,
    ); 

    if ( $Required == -1 ) {
        return $Self->IsRequiredForForm(
            FormName => $Param{FormName},
            DynamicField => $Param{DynamicField},
            Screen => 'Agent',
            Default => -1,
        );
    }
    if ( $Self->{Debug} > 0 ) { 
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message => "$Param{DynamicField}::$Required",
        );
    }

    return $Required;
}

sub GetQueue { 
    my ( $Self, %Param ) = @_; 
    for ( qw ( FormName ) ) { 
        if ( !$Param{$_} ) { 
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Missing $_!"); 
            return;
        }
    }

    my $Forms = $Self->{ConfigObject}->Get("MagicForms::Form"); 

    if ( $Forms->{$Param{FormName}} ) { 
        return $Forms->{$Param{FormName}}; 
    }

    # No form found, return nothing
    return; 
}
1;
