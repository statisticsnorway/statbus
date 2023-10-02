import React, { Component } from 'react'
import PropTypes from 'prop-types'
import { Form } from 'semantic-ui-react'

class FieldGroup extends Component {
  render() {
    const { isExtended, children } = this.props
    return (
      <Form.Group widths="equal">
        {children[0].key == 'statId' && children}
        {children[0].key == 'name' && children}
        {children[0].key == 'taxRegId' && children}
        {children[0].key == 'externalId' && children}
        {children[0].key == 'registrationReasonId' && children}
        {children[0].key == 'dataSourceClassificationId' && children}
        {children[0].key == 'legalUnitId' && children}
        {children[0].key == 'telephoneNo' && children}
        {children[0].key == 'address' && children}
        {children[0].key == 'actualAddress' && children}
        {children[0].key == 'postalAddress' && children}
        {/* {children[0].key == "activities" && children} */} {/* Does not work */}
        {children[0].key == 'sizeId' && children}
        {children[0].key == 'turnoverYear' && children}
        {children[0].key == 'numOfPeopleEmp' && children}
        {/* {children[0].key == "persons" && children} */} {/* Does not work */}
        {children[0].key == 'reorgTypeId' && children}
        {children[0].key == 'foreignParticipationId' && children}
        {children[0].key == 'notes' && children}
        {!isExtended && children.length % 2 !== 0 && <div className="field" />}
      </Form.Group>
    )
  }
}

const { bool, node } = PropTypes
FieldGroup.propTypes = {
  isExtended: bool.isRequired,
  children: node.isRequired,
}

export default FieldGroup
