import React from 'react'
import { func, bool } from 'prop-types'

import { wrapper } from 'helpers/locale'
import LinksForm from '../components/LinkForm'

class DeleteLink extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    deleteLink: func.isRequired,
    isLoading: bool.isRequired,
  }

  state = {
    data: undefined,
  }

  onChange = (value) => {
    this.setState({ data: value })
  }

  onSubmit = (value) => {
    const { deleteLink } = this.props
    deleteLink(value).then(() => this.onChange(undefined))
  }

  render() {
    const { localize, isLoading } = this.props
    const { data } = this.state
    return (
      <div>
        <LinksForm
          data={data}
          isLoading={isLoading}
          onChange={this.onChange}
          onSubmit={this.onSubmit}
          localize={localize}
          submitButtonText="ButtonDelete"
          submitButtonColor="red"
        />
      </div>
    )
  }
}

export default wrapper(DeleteLink)
