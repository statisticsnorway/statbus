import React from 'react'
import { Button, Form, Loader, Message } from 'semantic-ui-react'

export default class Edit extends React.Component {
  componentDidMount() {
    this.props.fetchRole(this.props.id)
  }
  render() {
    const { role, editForm, submitRole, message, status } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitRole(role)
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    return (
      <div>
        <h2>Edit role</h2>
        {role === undefined
          ? <Loader active />
          : <Form onSubmit={handleSubmit}>
            <Form.Input
              value={role.name}
              onChange={handleChange('name')}
              name="name"
              label="Role name"
              placeholder="e.g. Web Site Visitor"
            />
            <Form.Input
              value={role.description}
              onChange={handleChange('description')}
              name="description"
              label="Description"
              placeholder="e.g. Ordinary website user"
            />
            <Button type="submit" primary>Submit</Button>
            {message && <Message content={message} negative />}
          </Form>}
      </div>
    )
  }
}
