import React from 'react'
import { func, bool, shape, string } from 'prop-types'

import LinksForm from '../Components/LinkForm'
import { defaultUnitSearchResult } from '../Components/UnitSearch'

class DeleteLink extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    deleteLink: func.isRequired,
    isLoading: bool.isRequired,
    params: shape({
      id: string,
      type: string,
    }),
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
      statUnitType: this.props.params ? Number(this.props.params.type) : undefined,
      isDeleted: true,
    },
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

export default DeleteLink
