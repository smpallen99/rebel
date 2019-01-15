<% type_val =
  if type do
    "type: '#{type}',"
  else
    nil
 end
%>
swal({
  title: '<%= title %>',
  text: '<%= text %>',
  <%= type_val %>
  <%= for {k, v} <- opts do %>
  <%= "#{k}: #{v}" %>,
  <% end %>
})
<%= if confirm_function do %>
.then((data) => {
  let query_output = {};
  if (data.value) {
    let result = data.value;
    result.result = 'confirm';
    query_output = [window.rebel_modal.sender, result];
  } else {
    console.log('isConfirm false');
    query_output = [window.rebel_modal.sender, {
      result: 'cancel'
    }];
  }
  window.Rebel.return_channel.push("modal", { ok: query_output });
});
<% else %>
.then(() => {
    console.log('no confirm function');
    swal.close();
});
<% end %>
