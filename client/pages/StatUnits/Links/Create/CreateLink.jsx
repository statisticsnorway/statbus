import React from 'react'
import { func, array, bool } from 'prop-types'

import { wrapper } from 'helpers/locale'
import LinksGrid from '../Components/LinksGrid'
import LinksForm from '../Components/LinkForm'


class CreateLink extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    createLink: func.isRequired,
    deleteLink: func.isRequired,
    links: array.isRequired,
    isLoading: bool.isRequired,
  }

  state = {
    data: undefined,
  }

  onChange = (value) => {
    this.setState({ data: value })
  }

  render() {
    const { localize, links, createLink, deleteLink, isLoading } = this.props
    const { data } = this.state
    return (
      <div>
        <LinksForm
          data={data}
          isLoading={isLoading}
          onChange={this.onChange}
          onSubmit={createLink}
          localize={localize}
          submitButtonText="ButtonCreate"
          submitButtonColor="green"
        />
        <LinksGrid localize={localize} data={links} deleteLink={deleteLink} />
      </div>
    )
  }
}

export default wrapper(CreateLink)
