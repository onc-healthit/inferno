$(function(){

  function indent(value) {
    var firstCharacter = value.trim().charAt(0)
    try{
      if(['{','['].indexOf(firstCharacter) >= 0){
        return JSON.stringify(JSON.parse(value),null,2);
      } else {
        return value;
      }
    } catch (e) {
      return value;
    }
  }

  $('input[type=radio][name=confidential_client]').on('change', function() {
   switch($(this).val()) {
     case 'true':
       $('.client-secret-container').show();
       break;
     case 'false':
       $('.client-secret-container').hide();
       break;
   }
  });


  // $('.sequence-main').on('click', function(e) {
  //   if(e.target.getAttribute('role') !== 'button' && e.target.className !== 'result-details-clickable'){
  //     $(this).parent().find('.collapse').collapse('toggle');
  //   }
  // });

  $('.sequence-expand-button').click(function (event) {
    event.preventDefault();
    let button = $(this)
    let details = $('#' + button.data('result-details'))
    details.collapse('toggle');
    if (button.text().indexOf("Show") > -1) {
      button.html("Hide Details")
    }
    else {
      button.html("Show Details")
    }
  });

  $('.sequence-details-more').click(function () {
    var button = $(this);
    var sequence = button.data('sequence');

    if(sequence){
      $('.help-details').each(function(){
        if($(this).data('sequence') === sequence){
          $(this).show();
          $('#help-modal-title').html($(this).data('sequence-title'));

          // FIXME: technically we don't hae to do this every time it is opened, only the first time
          $(this).find('a[href^="http"]').attr('target','_blank');
        } else {
          $(this).hide();
        }
      })
      $('#help-sequence-' + sequence).collapse('show')

      $('#help-modal').modal('show');

    }
  });

  // $('.sequence-row').on('show.bs.collapse', function() {
  //   $(this).find('.oi-chevron-right').removeClass('oi-chevron-right').addClass('oi-chevron-bottom');
  // });

  // $('.sequence-row').on('hide.bs.collapse', function() {
  //   $(this).find('.oi-chevron-bottom').removeClass('oi-chevron-bottom').addClass('oi-chevron-right');
  // });

  $('.sequence-action button').click(function() {
    var sequence = $(this).data('sequence');
    // FIXME: This replaces the modal title with a regex'd sequence title, but it may not match (e.g., 'Dynamic Registration' vs. 'Dynamic Registration Sequence')
    $('#PrerequisitesModalTitle').html(sequence.replace(/(?<!^)([A-Z][a-z]|(?<=[a-z])[A-Z])/g, ' $1'))
    var requirements = []
    $('#PrerequisitesModal .form-group').each(function(){
      var requiredby = $(this).data('requiredby');
      var prerequisite = $(this).data('prerequisite');
      var show = false;
      if(requiredby){
        requiredby.split(',').forEach(function(item){
          if(item === sequence){
            show = true;
            requirements.push(prerequisite)
          }
        })
      }
      if(show){
        $(this).show()
      } else {
        $(this).hide();
      }
    });

    $('#PrerequisitesModal input[name=sequence]').val(sequence);
    $('#PrerequisitesModal input[name=required_fields]').val(requirements.join(','));

    // Confidential client special case
    if($('#confidential_client_on')[0].checked){
       $('.client-secret-container').show();
    } else {
       $('.client-secret-container').hide();
    }

    if(requirements.length === 0){
      $('#PrerequisitesModal form').submit();
    } else {
      $('#PrerequisitesModal').modal('show');
    }

  });

  $('.sequence-group-button').click(function(){
    var group = $(this).data('group'),
        sequences = [],
        requirements = [];

    $(this).closest('.sequence-group').find('.sequence-button').each(function(){
      sequences.push($(this).data('sequence'));
    });

    // FIXME: CONDENSE WITH THE INDIVIDUAL TEST RUN PORTION
    //
    $('#PrerequisitesModal .form-group').each(function(){
      var requiredby = $(this).data('requiredby');
      var definedby = $(this).data('definedby');
      var prerequisite = $(this).data('prerequisite');
      var definedList = [];
      var show = false;
      if(definedby){
        definedby.split(',').forEach(function(item){
          definedList.push(item);
        })
      }
      if(requiredby){
        requiredby.split(',').forEach(function(item){
          console.log(definedList);
          if(sequences.includes(item)){
            // this field is required by one of the sequences I'm running
            // is it also defined by one of the sequences?
            var alreadyDefined = false;
            definedList.forEach(function(defined){
              sequences.forEach(function(seq){
                if(defined === seq){
                  alreadyDefined = true;
                }
              })
            })
            if(!alreadyDefined){
              show = true;
              requirements.push(prerequisite)
            }
          }
        })
      }
      if(show){
        $(this).show()
      } else {
        $(this).hide();
      }
    });

    $('#PrerequisitesModal input[name=sequence]').val(sequences.join(','));
    $('#PrerequisitesModal input[name=group]').val(group);
    $('#PrerequisitesModal input[name=required_fields]').val(requirements.join(','));

    // Confidential client special case
    if($('#confidential_client_on')[0].checked){
       $('.client-secret-container').show();
    } else {
       $('.client-secret-container').hide();
    }

    if(requirements.length === 0){
      $('#PrerequisitesModal form').submit();
    } else {
      $('#PrerequisitesModal').modal('show');
    }
    $('#PrerequisitesModalTitle').html(group)
  })


  $('.disable-buttons').each(function(){
    $(this).find('.btn').attr('disabled', true)

    $(this).attr('title', $(this).data('preconditionDescription'))
                        .attr('data-toggle','tooltip');
  });

  $('.test-list li').on('click', function() {
    if($(this).data('testingInstanceId') && $(this).data('testResultId')){
      var url = window.basePath + '/' + $(this).data('testingInstanceId') + '/test_result/' + $(this).data('testResultId');
      $("#testResultDetailsModal").find('.modal-content').load(url, function(value){
        $(this).find("pre>code").each(function(el){
          let $el = $(this)
          let content = $el.html()
          try{
            if(content && content.length > 0){
              content = indent($el.html())
            }
          } catch (ex) {
            console.log('Error indenting: ' + ex)
          }
          $el.html(content)
        });

        $("#testResultDetailsModal").modal('show');
      })
    }
  })

  $(":input[type=text][readonly='readonly']").on('click', function(){
    this.select();
  })

  if(window.location.hash.length > 0){
    window.location.hash.split('#')[1].split(',').forEach(function(seq){
      var sequence = $('#' + seq);
      var details = $('#' + seq + '-details');
      details.collapse('show')
      sequence.parents('.sequence-row').find('.sequence-expand-button').text("Hide Details")
    })
  }

  $('[data-toggle="tooltip"]').tooltip()

  $('#WaitModal').modal('show');

}); 
