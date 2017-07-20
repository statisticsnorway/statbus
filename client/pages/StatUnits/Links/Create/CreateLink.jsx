import React from 'react'
import { func, arrayOf, shape, string, bool } from 'prop-types'

import { wrapper } from 'helpers/locale'
import LinksGrid from '../components/LinksGrid'
import LinksForm from '../components/LinkForm'
import { defaultUnitSearchResult } from '../components/UnitSearch'

class CreateLink extends React.Component {
  static propTypes = {
    links: arrayOf(shape({})).isRequired,
    isLoading: bool.isRequired,
    params: shape({
      id: string,
      type: string,
    }),
    createLink: func.isRequired,
    deleteLink: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    params: undefined,
  }

  state = {
    data: {
      source1: {
        ...defaultUnitSearchResult,
        id: this.props.params ? Number(this.props.params.id) : undefined,
        type: this.props.params ? Number(this.props.params.type) : undefined,
      },
      source2: defaultUnitSearchResult,
      comment: '',
    },
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
