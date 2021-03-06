MagicForms
===========

MagicForms is an OTRS (http://otrs.org) package/module plugin which provides a method to create dynamic forms in OTRS.  Typically this is a feature add-on or done through complex JavaScript/jQuery magic.  This method creates a new DTL file and the required Perl modules to power this as a server-side component!

Installation 
--------------

Install like any other module, this module should create a field called "MagicForms" this is important later on!

Configuration
--------------

For every queue you want to link your form to update your Config.pm or ZZZAuto file with the following: 
```perl
    # ---------------------------------------------------- #
    # MagicForms Static Config                             #
    # ---------------------------------------------------- #
    $Self->{'MagicForms::Form'} =  {
      'FormName'        => 'Queue1',
      'AnotherFormName' => 'Queue2',
      # Multiple forms can be pointed at the same queue
      'SomeForm'        => 'Queue2',
    };
```

Followed by a configuration for that queue (configuring the specific dynamic fields to show)
```perl
    # Fields set to the customer side will show as "Intake Fields" on the agent interface
    $Self->{'MagicForms::Customer::DynamicFieldToForm'} =  {
        'FormName' => {
            # 2 = required
            # 1 = present on form
            'RequiredField' => 2,
            'NonRequiredField' => 1,
            'AnotherFieldThatIsNotRequired' => 1,
            'AnotherRequiredField' => 2,
        },
        'SomeForm' => {
            'NonRequiredField' => 1,
            'AnotherFieldThatIsNotRequired' => 1,
            'AnotherRequiredField' => 2,
        },
    }
    
    # Fields set to the agent side will show as "Internal Fields" on the agent interface
    $Self->{'MagicForms::Agent::DynamicFieldToForm'} =  {
        'AnotherFormName' => {
            # 2 = required
            # 1 = present on form
            'RequiredField' => 2,
            'NonRequiredField' => 1,
            'AnotherFieldThatIsNotRequired' => 1,
            'AnotherRequiredField' => 2,
        },
        'SomeForm' => {
            'RequiredField' => 2,
        },
    };
```

Point your browser to your main portal **__your.install.com/otrs/customer.pll?Action=MagicFormsTicketMessage;MFForm=FormName__**

Where MFForm= _NameOfYourForm_

To make the customer fields visible update the *CustomerTicketZoom.dtl* With a link to the following: 
**__your.install.com/otrs/customer.pl?Action=CustomerIntakeFields;TicketID=$TicketId;FormName=DynamicField_MagicForms__**

