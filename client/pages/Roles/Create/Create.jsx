import React from 'react'
import { Button, Form, Message, Loader } from 'semantic-ui-react'

import rqst from '../../../helpers/fetch'

export default class CreateForm extends React.Component {
  state = {
    systemFunctions: [],
    fetchingSystemFunctions: true,
    systemFunctionsFailMessage: undefined,
  }
  componentDidMount() {
    this.fetchingSystemFunctions()
  }
  fetchingSystemFunctions() {
    rqst({
      url: '/api/accessAttributes/systemFunctions',
      onSuccess: (result) => { this.setState(s => ({
        ...s,
        systemFunctions: result,
        fetchingSystemFunctions: false,
      })) },
      onFail: () => { this.setState(s => ({
        ...s,
        systemFunctionsFailMessage: 'failed loading system functions',
        fetchingSystemFunctions: false,
      })) },
      onError: () => { this.setState(s => ({
        ...s,
        systemFunctionsFailMessage: 'error while fetching system functions',
        fetchingSystemFunctions: false,
      })) },
    })
  }
  render() {
    const { submitRole, message, status } = this.props
    const handleSubmit = (e, serialized) => {
      e.preventDefault()
      submitRole(serialized)
    }
    return (
      <div>
        <h2>Create new role</h2>
        <Form onSubmit={handleSubmit}>
          <Form.Input
            name="name"
            label="Role name"
            placeholder="e.g. Web Site Visitor"
          />
          <Form.Input
            name="description"
            label="Description"
            placeholder="e.g. Ordinary website user"
          />
          {this.state.fetchingSystemFunctions
            ? <Loader content="fetching system functions" />
            : <Form.Select
              options={this.state.systemFunctions.map(r => ({ value: r.key, text: r.value }))}
              name="accessToSystemFunctions"
              label="Access ToSystem Functions"
              placeholder="select or search system functions..."
              multiple
              search
            />}
          <Button type="submit" primary>Submit</Button>
          {message && <Message content={message} negative />}
        </Form>
      </div>
    )
  }
}
