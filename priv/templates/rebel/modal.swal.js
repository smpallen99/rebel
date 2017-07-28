swal({
  title: '<%= title %>',
  text: '<%= text %>',
  type: '<%= type %>',
  <%= for {k, v} <- opts do %>
  <%= "#{k}: #{v}" %>,
  <% end %>
}
<%= if confirm_function do %>
, function(isConfirm){
  if (isConfirm) {
    var query_output = [window.rebel_modal.sender, {
      result: 'confirm'
    }];
    window.Rebel.channels.user.channel.push("modal", { ok: query_output });
  } else {
    var query_output = [window.rebel_modal.sender, {
      result: 'cancel'
    }];
    window.Rebel.channels.user.channel.push("modal", { ok: query_output });
  }
}
<% else %>
, function() {
    var query_output = [window.rebel_modal.sender, {
      result: 'ok'
    }];
    window.Rebel.channels.user.channel.push("modal", { ok: query_output });
    swal.close()
}
<% end %>
);
