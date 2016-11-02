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
    return role !== undefined
      ? (
        <Form onSubmit={handleSubmit}>
          <Form.Field>
            <label htmlFor="roleNameInput">Role name</label>
            <input
              id="roleNameInput"
              placeholder="e.g. Web Site Visitor"
              name="name"
              value={role.name}
              onChange={handleChange('name')}
            />
          </Form.Field>
          <Form.Field>
            <label htmlFor="roleDescriptionInput">Description</label>
            <input
              id="roleDescriptionInput"
              placeholder="e.g. Ordinary website user"
              name="description"
              value={role.description}
              onChange={handleChange('description')}
            />
          </Form.Field>
          <Button type="submit" primary>Submit</Button>
          {message && <Message content={message} />}
        </Form>
      ) : <Loader active />
  }
}
