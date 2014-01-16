function update_chatlog(user, data, level) {
var label = '';
/*
0 = you
1 = them
2 = staff
*/
switch(level){
  case 0:
    label = 'info';
    break;
  case 1:
    label = 'primary';
    break
  case 2:
    label = 'danger';
    break;
  default:
    label = 'info';
}
  $("#chatlog_window .mCSB_container").append('<div class="my-well"><button class="btn btn-'+label+' btn-xs">'+user+'</button> '+data+' </div>');
  setTimeout( function () { $("#chatlog_window").mCustomScrollbar("scrollTo","button:last",{scrollInertia:2500,scrollEasing:"easeInOutQuad"}); }, 500 );
}

function update_chatlog_alert(user, data) {

  $("#chatlog_window .mCSB_container").append('<div class="alert-well"><button class="btn btn-danger btn-xs">'+user+'</button> '+data+' </div>');
  setTimeout( function () { $("#chatlog_window").mCustomScrollbar("scrollTo","button:last",{scrollInertia:2500,scrollEasing:"easeInOutQuad"}); }, 500 );
}

function send_message(e) {
  console.log(e);
  if(e.keyCode == 13 ) { console.log('someone hit enter'); }
}

(function($){
  $(window).load(function(){
    $(".ft-window").mCustomScrollbar({
      scrollButtons:{
        enable:true
      },
      advanced:{
        updateOnContentResize: Boolean
      },
      scrollInertia: 0,
      theme:"light-thick"
  
    });
  });

setTimeout( function () { $("#chatlog_window").mCustomScrollbar("scrollTo","button:last",{scrollInertia:2500,scrollEasing:"easeInOutQuad"}); }, 500 );

})(jQuery);